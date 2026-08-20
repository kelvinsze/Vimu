import Foundation
import Network
import OSLog

private let logger = Logger(subsystem: "com.kelvinsze.vimu", category: "HTTPServer")

/// Embedded lightweight HTTP server using Network.framework for UPnP Device Description & SOAP endpoints.
public final class HTTPServer: @unchecked Sendable {
    public static let shared = HTTPServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.kelvinsze.vimu.httpserver", qos: .userInitiated)
    private var isRunning = false
    public private(set) var port: UInt16 = 7890

    public var localIPAddress: String {
        return NetworkHelper.getWiFiAddress() ?? "127.0.0.1"
    }

    private init() {}

    public func start(port: UInt16 = 7890) {
        guard !isRunning else { return }
        self.port = port
        UPnPDevice.shared.serverPort = port

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                logger.error("Invalid port: \(port)")
                return
            }

            let newListener = try NWListener(using: parameters, on: nwPort)
            newListener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isRunning = true
                    logger.info("Vimu HTTP Server listening on port \(port). IP: \(self?.localIPAddress ?? "unknown")")
                case .failed(let error):
                    logger.error("HTTP Server listener failed: \(error.localizedDescription)")
                    self?.isRunning = false
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleIncomingConnection(connection)
            }

            newListener.start(queue: queue)
            self.listener = newListener
        } catch {
            logger.error("Failed to start HTTP server: \(error.localizedDescription)")
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        logger.info("HTTP Server stopped.")
    }

    private func handleIncomingConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        readHTTPRequest(connection: connection, accumulatedData: Data())
    }

    private func readHTTPRequest(connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }
            var currentData = accumulatedData
            if let content = content {
                currentData.append(content)
            }

            // Check if headers are completely received
            if let headerEndRange = currentData.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = currentData.subdata(in: 0..<headerEndRange.lowerBound)
                let bodyData = currentData.subdata(in: headerEndRange.upperBound..<currentData.count)

                guard let headerString = String(data: headerData, encoding: .utf8) else {
                    self.sendResponse(connection: connection, statusCode: 400, contentType: "text/plain", body: "Bad Request")
                    return
                }

                // Parse content length
                let headers = self.parseHeaders(headerString)
                let contentLength = Int(headers["content-length"] ?? "0") ?? 0

                if bodyData.count >= contentLength {
                    self.processRequest(connection: connection, headerString: headerString, headers: headers, bodyData: bodyData)
                } else {
                    // Need more body data
                    self.readHTTPRequest(connection: connection, accumulatedData: currentData)
                }
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                // Continue reading headers
                self.readHTTPRequest(connection: connection, accumulatedData: currentData)
            }
        }
    }

    private func parseHeaders(_ rawHeader: String) -> [String: String] {
        var headers: [String: String] = [:]
        let lines = rawHeader.components(separatedBy: "\r\n")
        for line in lines.dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                headers[parts[0].lowercased()] = parts[1]
            }
        }
        return headers
    }

    private func processRequest(connection: NWConnection, headerString: String, headers: [String: String], bodyData: Data) {
        let firstLine = headerString.components(separatedBy: "\r\n").first ?? ""
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, statusCode: 400, contentType: "text/plain", body: "Bad Request")
            return
        }

        let method = String(parts[0]).uppercased()
        let path = String(parts[1])
        logger.info("HTTP Request: \(method) \(path)")

        switch (method, path) {
        case ("GET", "/description.xml"):
            let xml = UPnPDevice.shared.deviceDescriptionXML(hostIP: localIPAddress)
            sendResponse(connection: connection, statusCode: 200, contentType: "text/xml; charset=\"utf-8\"", body: xml)

        case ("GET", "/avtransport.xml"):
            let xml = UPnPDevice.shared.avTransportSCPD()
            sendResponse(connection: connection, statusCode: 200, contentType: "text/xml; charset=\"utf-8\"", body: xml)

        case ("GET", "/renderingcontrol.xml"):
            let xml = UPnPDevice.shared.renderingControlSCPD()
            sendResponse(connection: connection, statusCode: 200, contentType: "text/xml; charset=\"utf-8\"", body: xml)

        case ("GET", "/connectionmanager.xml"):
            let xml = UPnPDevice.shared.connectionManagerSCPD()
            sendResponse(connection: connection, statusCode: 200, contentType: "text/xml; charset=\"utf-8\"", body: xml)

        case ("POST", let p) where p.hasPrefix("/upnp/control/"):
            let soapActionHeader = headers["soapaction"]
            if let action = SOAPParser.parseAction(bodyData: bodyData, soapActionHeader: soapActionHeader) {
                Task {
                    let result = await AVTransportService.shared.handleRequest(action: action)
                    self.sendResponse(connection: connection, statusCode: result.statusCode, contentType: "text/xml; charset=\"utf-8\"", body: result.responseBody)
                }
            } else {
                let fault = SOAPParser.makeSOAPFault(errorCode: 401, errorDescription: "Invalid Action")
                sendResponse(connection: connection, statusCode: 500, contentType: "text/xml; charset=\"utf-8\"", body: fault)
            }

        case ("GET", "/status"):
            let status = "{\"status\":\"ok\",\"ip\":\"\(localIPAddress)\",\"port\":\(port)}"
            sendResponse(connection: connection, statusCode: 200, contentType: "application/json", body: status)

        default:
            sendResponse(connection: connection, statusCode: 404, contentType: "text/plain", body: "Not Found")
        }
    }

    private func sendResponse(connection: NWConnection, statusCode: Int, contentType: String, body: String) {
        let statusText = statusCode == 200 ? "OK" : (statusCode == 404 ? "Not Found" : "Internal Server Error")
        let bodyData = Data(body.utf8)
        let responseHeader = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Server: iOS/17 UPnP/1.0 Vimu/0.1\r
        Content-Type: \(contentType)\r
        Content-Length: \(bodyData.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r\n
        """

        var fullData = Data(responseHeader.utf8)
        fullData.append(bodyData)

        connection.send(content: fullData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

// MARK: - Network IP Helper

public enum NetworkHelper {
    public static func getWiFiAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                // en0 is Wi-Fi on iOS devices
                if name == "en0" || name == "pdp_ip0" || name == "lo0" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                    let ip = String(cString: hostname)
                    if name == "en0" {
                        return ip // Wi-Fi preferred
                    } else if address == nil {
                        address = ip
                    }
                }
            }
        }
        return address
    }
}
