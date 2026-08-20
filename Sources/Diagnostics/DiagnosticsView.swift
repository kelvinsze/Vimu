import SwiftUI
import Network

/// Diagnostics dashboard for troubleshooting network routing, SSDP, and loopback casting.
public struct DiagnosticsView: View {
    @State private var localIP = HTTPServer.shared.localIPAddress
    @State private var interfaces: [NetworkInterfaceInfo] = []
    @State private var diagnosticLog: [String] = []
    @State private var isRunningTest = false

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("Active Network Interfaces") {
                    ForEach(interfaces) { iface in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(iface.name)
                                    .font(.subheadline.bold())
                                Text(iface.type)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(iface.ipAddress)
                                .font(.subheadline.monospaced())
                        }
                    }

                    if interfaces.isEmpty {
                        Text("No active interfaces detected.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Receiver Diagnostics") {
                    HStack {
                        Text("HTTP Server Status")
                        Spacer()
                        Text("Running on :\(HTTPServer.shared.port)")
                            .foregroundColor(.green)
                    }

                    HStack {
                        Text("SSDP Multicast Group")
                        Spacer()
                        Text("239.255.255.250:1900")
                            .font(.caption.monospaced())
                    }

                    Button {
                        runLoopbackTest()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Run Local Loopback Test")
                        }
                    }
                    .disabled(isRunningTest)
                }

                Section("Diagnostic Logs") {
                    if diagnosticLog.isEmpty {
                        Text("No diagnostic events yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(Array(diagnosticLog.enumerated()), id: \.offset) { _, log in
                            Text(log)
                                .font(.caption.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("Diagnostics")
            .onAppear {
                refreshInterfaces()
            }
        }
    }

    private func refreshInterfaces() {
        localIP = HTTPServer.shared.localIPAddress
        var results: [NetworkInterfaceInfo] = []

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
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
                let type: String
                if name.hasPrefix("en") { type = "Wi-Fi / Ethernet" }
                else if name.hasPrefix("pdp_ip") { type = "Cellular" }
                else if name.hasPrefix("lo") { type = "Loopback" }
                else { type = "Other" }

                results.append(NetworkInterfaceInfo(name: name, type: type, ipAddress: ip))
            }
        }
        self.interfaces = results
    }

    private func runLoopbackTest() {
        isRunningTest = true
        addLog("Starting local loopback SOAP test...")

        Task {
            let url = URL(string: "http://127.0.0.1:\(HTTPServer.shared.port)/upnp/control/avtransport")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
            request.setValue("\"urn:schemas-upnp-org:service:AVTransport:1#GetTransportInfo\"", forHTTPHeaderField: "SOAPACTION")

            let soapBody = """
            <?xml version="1.0" encoding="utf-8"?>
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
              <s:Body>
                <u:GetTransportInfo xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
                  <InstanceID>0</InstanceID>
                </u:GetTransportInfo>
              </s:Body>
            </s:Envelope>
            """
            request.httpBody = Data(soapBody.utf8)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    addLog("Loopback response HTTP \(httpResponse.statusCode)")
                    if let str = String(data: data, encoding: .utf8) {
                        addLog("Received SOAP XML: \(str.prefix(120))...")
                    }
                }
            } catch {
                addLog("Loopback test failed: \(error.localizedDescription)")
            }

            isRunningTest = false
        }
    }

    private func addLog(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        diagnosticLog.insert("[\(timestamp)] \(message)", at: 0)
    }
}

public struct NetworkInterfaceInfo: Identifiable {
    public var id: String { "\(name)_\(ipAddress)" }
    public let name: String
    public let type: String
    public let ipAddress: String
}
