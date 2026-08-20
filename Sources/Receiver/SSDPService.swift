import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "SSDPService")

/// Manages SSDP (Simple Service Discovery Protocol) on 239.255.255.250:1900
/// to announce Vimu MediaRenderer and respond to M-SEARCH queries.
public final class SSDPService: @unchecked Sendable {
    public static let shared = SSDPService()

    private let multicastIP = "239.255.255.250"
    private let multicastPort: UInt16 = 1900
    private let queue = DispatchQueue(label: "com.kelvinsze.vimu.ssdp", qos: .userInitiated)

    private var connectionGroup: NWConnectionGroup?
    private var isRunning = false
    private var advertiseTimer: DispatchSourceTimer?

    private init() {}

    public func start() {
        guard !isRunning else { return }
        logger.info("Starting SSDP Service...")

        do {
            guard let group = try? NWMulticastGroup(for: [.hostPort(host: .init(multicastIP), port: .init(integerLiteral: multicastPort))]) else {
                logger.error("Failed to create NWMulticastGroup for SSDP.")
                return
            }

            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true

            let connectionGroup = NWConnectionGroup(with: group, using: params)
            connectionGroup.setReceiveHandler(maximumMessageSize: 4096, rejectOversizedMessages: true) { [weak self] message, content, isComplete in
                if let content = content, let text = String(data: content, encoding: .utf8) {
                    self?.handleIncomingPacket(text, message: message)
                }
            }

            connectionGroup.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isRunning = true
                    logger.info("SSDP Multicast listener ready on 239.255.255.250:1900.")
                    self?.startAdvertisingTimer()
                    self?.sendSSDPAlive()
                case .failed(let error):
                    logger.error("SSDP ConnectionGroup failed: \(error.localizedDescription)")
                    self?.isRunning = false
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }

            connectionGroup.start(queue: queue)
            self.connectionGroup = connectionGroup
        }
    }

    public func stop() {
        advertiseTimer?.cancel()
        advertiseTimer = nil

        sendSSDPByeBye()

        connectionGroup?.cancel()
        connectionGroup = nil
        isRunning = false
        logger.info("SSDP Service stopped.")
    }

    // MARK: - M-SEARCH Handling

    private func handleIncomingPacket(_ packet: String, message: NWConnectionGroup.Message) {
        let lines = packet.components(separatedBy: "\r\n")
        guard let firstLine = lines.first, firstLine.uppercased().hasPrefix("M-SEARCH") else {
            return
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                headers[parts[0].uppercased()] = parts[1]
            }
        }

        guard let man = headers["MAN"], man.contains("ssdp:discover"),
              let st = headers["ST"] else {
            return
        }

        logger.info("Received M-SEARCH for ST: \(st)")
        respondToMSearch(st: st, message: message)
    }

    private func respondToMSearch(st: String, message: NWConnectionGroup.Message) {
        let device = UPnPDevice.shared
        let ip = HTTPServer.shared.localIPAddress
        let port = HTTPServer.shared.port
        let location = "http://\(ip):\(port)/description.xml"

        let targetTypes: [(st: String, usn: String)] = [
            ("upnp:rootdevice", "\(device.udn)::upnp:rootdevice"),
            (device.udn, device.udn),
            ("urn:schemas-upnp-org:device:MediaRenderer:1", "\(device.udn)::urn:schemas-upnp-org:device:MediaRenderer:1"),
            ("urn:schemas-upnp-org:service:AVTransport:1", "\(device.udn)::urn:schemas-upnp-org:service:AVTransport:1"),
            ("urn:schemas-upnp-org:service:RenderingControl:1", "\(device.udn)::urn:schemas-upnp-org:service:RenderingControl:1"),
            ("urn:schemas-upnp-org:service:ConnectionManager:1", "\(device.udn)::urn:schemas-upnp-org:service:ConnectionManager:1")
        ]

        for target in targetTypes {
            if st == "ssdp:all" || st == target.st {
                let response = """
                HTTP/1.1 200 OK\r
                CACHE-CONTROL: max-age=1800\r
                DATE: \(httpDateString())\r
                EXT:\r
                LOCATION: \(location)\r
                SERVER: iOS/17 UPnP/1.0 Vimu/0.1\r
                ST: \(target.st)\r
                USN: \(target.usn)\r
                BOOTID.UPNP.ORG: 1\r
                \r\n
                """

                if let data = response.data(using: .utf8) {
                    message.reply(content: data)
                }
            }
        }
    }

    // MARK: - SSDP Periodic NOTIFY

    private func startAdvertisingTimer() {
        advertiseTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 60)
        timer.setEventHandler { [weak self] in
            self?.sendSSDPAlive()
        }
        timer.resume()
        self.advertiseTimer = timer
    }

    private func sendSSDPAlive() {
        sendNotification(nts: "ssdp:alive")
    }

    private func sendSSDPByeBye() {
        sendNotification(nts: "ssdp:byebye")
    }

    private func sendNotification(nts: String) {
        guard let group = connectionGroup else { return }
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

            if let data = notify.data(using: .utf8) {
                group.send(content: data) { error in
                    if let error = error {
                        logger.debug("NOTIFY broadcast error: \(error.localizedDescription)")
                    }
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
