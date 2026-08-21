import Foundation
import UIKit

/// Manages UPnP MediaRenderer metadata, UUID, and SCPD XML descriptors.
public final class UPnPDevice: @unchecked Sendable {
    public static let shared = UPnPDevice()

    public let uuid: String
    public var friendlyName: String
    public var manufacturer: String = "Vimu Project"
    public var modelName: String = "Vimu CarPlay MediaRenderer"
    public var modelNumber: String = "1.0"
    public var serverPort: UInt16 = 7890

    private init() {
        if let savedUUID = UserDefaults.standard.string(forKey: "vimu_upnp_uuid") {
            self.uuid = savedUUID
        } else {
            let newUUID = UUID().uuidString.lowercased()
            UserDefaults.standard.set(newUUID, forKey: "vimu_upnp_uuid")
            self.uuid = newUUID
        }

        let deviceName = UIDevice.current.name
        self.friendlyName = "Vimu (\(deviceName))"
    }

    public var udn: String {
        return "uuid:\(uuid)"
    }

    /// Generates UPnP root device description XML.
    public func deviceDescriptionXML(hostIP: String) -> String {
        let location = "http://\(hostIP):\(serverPort)"
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <root xmlns="urn:schemas-upnp-org:device-1-0">
          <specVersion>
            <major>1</major>
            <minor>0</minor>
          </specVersion>
          <device>
            <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
            <friendlyName>\(escapeXML(friendlyName))</friendlyName>
            <manufacturer>\(escapeXML(manufacturer))</manufacturer>
            <manufacturerURL>https://vimu.app</manufacturerURL>
            <modelDescription>Vimu Local Network &amp; CarPlay Video MediaRenderer</modelDescription>
            <modelName>\(escapeXML(modelName))</modelName>
            <modelNumber>\(modelNumber)</modelNumber>
            <modelURL>https://vimu.app</modelURL>
            <UDN>\(udn)</UDN>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
                <SCPDURL>/avtransport.xml</SCPDURL>
                <controlURL>/upnp/control/avtransport</controlURL>
              </service>
              <service>
                <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
                <SCPDURL>/renderingcontrol.xml</SCPDURL>
                <controlURL>/upnp/control/renderingcontrol</controlURL>
              </service>
              <service>
                <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>
                <SCPDURL>/connectionmanager.xml</SCPDURL>
                <controlURL>/upnp/control/connectionmanager</controlURL>
              </service>
            </serviceList>
          </device>
        </root>
        """
    }

    /// Generates AVTransport:1 Service Control Protocol Description (SCPD).
    public func avTransportSCPD() -> String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <scpd xmlns="urn:schemas-upnp-org:service-1-0">
          <specVersion>
            <major>1</major>
            <minor>0</minor>
          </specVersion>
          <actionList>
            <action><name>SetAVTransportURI</name></action>
            <action><name>Play</name></action>
            <action><name>Pause</name></action>
            <action><name>Stop</name></action>
            <action><name>Seek</name></action>
            <action><name>GetTransportInfo</name></action>
            <action><name>GetPositionInfo</name></action>
            <action><name>GetMediaInfo</name></action>
            <action><name>GetTransportSettings</name></action>
          </actionList>
        </scpd>
        """
    }

    /// Generates RenderingControl:1 SCPD.
    public func renderingControlSCPD() -> String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <scpd xmlns="urn:schemas-upnp-org:service-1-0">
          <specVersion>
            <major>1</major>
            <minor>0</minor>
          </specVersion>
          <actionList>
            <action><name>SetVolume</name></action>
            <action><name>GetVolume</name></action>
            <action><name>SetMute</name></action>
            <action><name>GetMute</name></action>
          </actionList>
        </scpd>
        """
    }

    /// Generates ConnectionManager:1 SCPD.
    public func connectionManagerSCPD() -> String {
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <scpd xmlns="urn:schemas-upnp-org:service-1-0">
          <specVersion>
            <major>1</major>
            <minor>0</minor>
          </specVersion>
          <actionList>
            <action><name>GetProtocolInfo</name></action>
            <action><name>GetCurrentConnectionIDs</name></action>
            <action><name>GetCurrentConnectionInfo</name></action>
          </actionList>
        </scpd>
        """
    }

    private func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
