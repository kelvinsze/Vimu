import Foundation
import Network
import OSLog
import Combine

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "SSDPService")

/// Robust multi-tiered SSDP (Simple Service Discovery Protocol) & Bonjour broadcaster.
/// Supports POSIX UDP Socket, NWConnectionGroup, Subnet Broadcasts, and mDNS announcements.
public final class SSDPService: NSObject, @unchecked Sendable, NetServiceDelegate {
    public static let shared = SSDPService()

    private let multicastIP = "239.255.255.250"
    private let multicastPort: UInt16 = 1900
    private let queue = DispatchQueue(label: "com.kelvinsze.vimu.ssdp", qos: .userInitiated)

    private var connectionGroup: NWConnectionGroup?
    private var isRunning = false
    private var advertiseTimer: DispatchSourceTimer?
    private var bsdSocketFD: Int32 = -1
    private var bsdReadSource: DispatchSourceRead?
    private var upnpNetService: NetService?

    // Recent discovery logs for Diagnostics
    public var onDiscoveryEvent: ((String) -> Void)?

    public static func parseMSearchTarget(_ packet: String) -> String? {
        let lines = packet.components(separatedBy: "\r\n")
        guard let firstLine = lines.first, firstLine.uppercased().hasPrefix("M-SEARCH") else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { headers[parts[0].uppercased()] = parts[1] }
        }
        guard let man = headers["MAN"], man.lowercased().contains("ssdp:discover") else { return nil }
        return headers["ST"]
    }

    public static func targetTypes(for udn: String) -> [(st: String, usn: String)] {
        [("upnp:rootdevice", "\(udn)::upnp:rootdevice"), (udn, udn),
         ("urn:schemas-upnp-org:device:MediaRenderer:1", "\(udn)::urn:schemas-upnp-org:device:MediaRenderer:1"),
         ("urn:schemas-upnp-org:service:AVTransport:1", "\(udn)::urn:schemas-upnp-org:service:AVTransport:1"),
         ("urn:schemas-upnp-org:service:RenderingControl:1", "\(udn)::urn:schemas-upnp-org:service:RenderingControl:1"),
         ("urn:schemas-upnp-org:service:ConnectionManager:1", "\(udn)::urn:schemas-upnp-org:service:ConnectionManager:1")]
    }

    public static func mSearchResponses(for st: String, udn: String, location: String, date: String) -> [Data] {
        targetTypes(for: udn).compactMap { target in
            guard st == "ssdp:all" || st == target.st else { return nil }
            return "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=1800\r\nDATE: \(date)\r\nEXT:\r\nLOCATION: \(location)\r\nSERVER: iOS/17 UPnP/1.0 Vimu/0.1\r\nST: \(target.st)\r\nUSN: \(target.usn)\r\nBOOTID.UPNP.ORG: 1\r\n\r\n".data(using: .utf8)
        }
    }

    private override init() {
        super.init()
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        logger.info("Starting Multi-Tier SSDP & Bonjour Service...")

        // 1. Start POSIX BSD UDP Multicast Socket listener on port 1900
        startBSDSocketListener()

        // 2. Start NWConnectionGroup (Network.framework)
        startNWConnectionGroup()

        // 3. Start Bonjour / mDNS publication
        startBonjourAnnouncement()

        // 4. Start periodic advertising timer (frequent initial bursts, then periodic)
        startAdvertisingTimer()

        // Send immediate SSDP alive announcements
        sendSSDPAlive()
    }

    public func stop() {
        advertiseTimer?.cancel()
        advertiseTimer = nil

        sendSSDPByeBye()

        stopBSDSocketListener()
        stopNWConnectionGroup()
        stopBonjourAnnouncement()

        isRunning = false
        logger.info("SSDP Service stopped.")
    }

    // MARK: - 1. POSIX BSD UDP Socket Listener (Multicast + Broadcast fallback)

    private func startBSDSocketListener() {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            logger.error("Failed to create BSD socket: \(errno)")
            return
        }

        var reuseOn: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseOn, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuseOn, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &reuseOn, socklen_t(MemoryLayout<Int32>.size))

        // Bind to INADDR_ANY:1900
        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_port = in_port_t(multicastPort).bigEndian
        bindAddr.sin_addr.s_addr = in_addr_t(0) // INADDR_ANY

        let bindResult = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if bindResult < 0 {
            logger.warning("BSD socket bind on 1900 returned \(errno). Attempting join...")
        }

        // Join multicast group 239.255.255.250
        var mreq = ip_mreq()
        mreq.imr_multiaddr.s_addr = inet_addr(multicastIP)
        mreq.imr_interface.s_addr = in_addr_t(0)
        setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &mreq, socklen_t(MemoryLayout<ip_mreq>.size))

        self.bsdSocketFD = fd

        // Read source via DispatchSource
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleBSDSocketReadable()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.bsdReadSource = source
        logger.info("BSD POSIX UDP Socket listener active on port 1900.")
    }

    private func handleBSDSocketReadable() {
        guard bsdSocketFD >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 4096)
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let bytesRead = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(bsdSocketFD, &buffer, buffer.count, 0, $0, &addrLen)
            }
        }

        guard bytesRead > 0 else { return }
        if let packet = String(bytes: buffer[0..<bytesRead], encoding: .utf8) {
            processIncomingPacket(packet, clientAddr: clientAddr)
        }
    }

    private func processIncomingPacket(_ packet: String, clientAddr: sockaddr_in) {
        guard let st = Self.parseMSearchTarget(packet) else { return }

        let eventLog = "M-SEARCH for ST: \(st)"
        logger.info("\(eventLog)")
        onDiscoveryEvent?(eventLog)

        respondToMSearchViaBSDSocket(st: st, clientAddr: clientAddr)
    }

    private func respondToMSearchViaBSDSocket(st: String, clientAddr: sockaddr_in) {
        let device = UPnPDevice.shared
        let ip = HTTPServer.shared.localIPAddress
        let port = HTTPServer.shared.port
        let location = "http://\(ip):\(port)/description.xml"


        var targetAddr = clientAddr
        for data in Self.mSearchResponses(for: st, udn: device.udn, location: location, date: httpDateString()) where bsdSocketFD >= 0 {
            data.withUnsafeBytes { rawPtr in
                _ = withUnsafePointer(to: &targetAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(bsdSocketFD, rawPtr.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }

    private func stopBSDSocketListener() {
        bsdReadSource?.cancel()
        bsdReadSource = nil
        bsdSocketFD = -1
    }

    // MARK: - 2. NWConnectionGroup

    private func startNWConnectionGroup() {
        guard let group = try? NWMulticastGroup(for: [.hostPort(host: .init(multicastIP), port: .init(integerLiteral: multicastPort))]) else {
            return
        }

        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true

        let connectionGroup = NWConnectionGroup(with: group, using: params)
        connectionGroup.setReceiveHandler(maximumMessageSize: 4096, rejectOversizedMessages: true) { [weak self] message, content, isComplete in
            if let content = content, let text = String(data: content, encoding: .utf8) {
                self?.handleNWPacket(text, message: message)
            }
        }

        connectionGroup.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                logger.info("NWConnectionGroup ready.")
            case .failed(let error):
                logger.debug("NWConnectionGroup failed: \(error.localizedDescription)")
            default:
                break
            }
        }

        connectionGroup.start(queue: queue)
        self.connectionGroup = connectionGroup
    }

    private func handleNWPacket(_ packet: String, message: NWConnectionGroup.Message) {
        guard let st = Self.parseMSearchTarget(packet) else { return }
        onDiscoveryEvent?("NW M-SEARCH for ST: \(st)")

        let device = UPnPDevice.shared
        let ip = HTTPServer.shared.localIPAddress
        let port = HTTPServer.shared.port
        let location = "http://\(ip):\(port)/description.xml"


        for data in Self.mSearchResponses(for: st, udn: device.udn, location: location, date: httpDateString()) {
            message.reply(content: data)
        }
    }

    private func stopNWConnectionGroup() {
        connectionGroup?.cancel()
        connectionGroup = nil
    }

    // MARK: - 3. Bonjour / mDNS Service

    private func startBonjourAnnouncement() {
        let name = UPnPDevice.shared.friendlyName
        let port = Int32(HTTPServer.shared.port)
        let netService = NetService(domain: "local.", type: "_upnp._tcp.", name: name, port: port)
        netService.delegate = self
        netService.publish(options: [])
        self.upnpNetService = netService
    }

    private func stopBonjourAnnouncement() {
        upnpNetService?.stop()
        upnpNetService = nil
    }

    // MARK: - 4. Subnet & Multicast Active NOTIFY Broadcasts

    private func startAdvertisingTimer() {
        advertiseTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Repeat every 5 seconds for snappy local network discovery
        timer.schedule(deadline: .now() + 1, repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.sendSSDPAlive()
        }
        timer.resume()
        self.advertiseTimer = timer
    }

    public func sendSSDPAlive() {
        sendNotification(nts: "ssdp:alive")
    }

    public func sendSSDPByeBye() {
        sendNotification(nts: "ssdp:byebye")
    }

    private func sendNotification(nts: String) {
        let device = UPnPDevice.shared
        let ip = HTTPServer.shared.localIPAddress
        let port = HTTPServer.shared.port
        let location = "http://\(ip):\(port)/description.xml"

        let targetTypes: [(nt: String, usn: String)] = [
            ("upnp:rootdevice", "\(device.udn)::upnp:rootdevice"),
            (device.udn, device.udn),
            ("urn:schemas-upnp-org:device:MediaRenderer:1", "\(device.udn)::urn:schemas-upnp-org:device:MediaRenderer:1"),
            ("urn:schemas-upnp-org:service:AVTransport:1", "\(device.udn)::urn:schemas-upnp-org:service:AVTransport:1")
        ]

        for target in targetTypes {
            let notify = """
            NOTIFY * HTTP/1.1\r
            HOST: 239.255.255.250:1900\r
            CACHE-CONTROL: max-age=1800\r
            LOCATION: \(location)\r
            NT: \(target.nt)\r
            NTS: \(nts)\r
            SERVER: iOS/17 UPnP/1.0 Vimu/0.1\r
            USN: \(target.usn)\r
            BOOTID.UPNP.ORG: 1\r
            \r\n
            """

            guard let data = notify.data(using: .utf8) else { continue }

            // 1. Send via NWConnectionGroup
            connectionGroup?.send(content: data) { _ in }

            // 2. Broadcast via BSD Socket to Multicast 239.255.255.250 and Local Broadcast 255.255.255.255
            if bsdSocketFD >= 0 {
                sendUDPBytes(data, toIP: multicastIP, port: multicastPort)
                sendUDPBytes(data, toIP: "255.255.255.255", port: multicastPort)
            }
        }
    }

    private func sendUDPBytes(_ data: Data, toIP: String, port: UInt16) {
        guard bsdSocketFD >= 0 else { return }
        var targetAddr = sockaddr_in()
        targetAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        targetAddr.sin_family = sa_family_t(AF_INET)
        targetAddr.sin_port = in_port_t(port).bigEndian
        targetAddr.sin_addr.s_addr = inet_addr(toIP)

        data.withUnsafeBytes { rawPtr in
            _ = withUnsafePointer(to: &targetAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(bsdSocketFD, rawPtr.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private func httpDateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: Date())
    }
}
