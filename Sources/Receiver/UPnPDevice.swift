import Foundation
import UIKit

/// Manages UPnP MediaRenderer metadata, UUID, and SCPD XML descriptors.
public final class UPnPDevice: @unchecked Sendable {
    public static let shared = UPnPDevice()

    public let uuid: String
    public var friendlyName: String
    public var manufacturer: String = "Mivu Project"
    public var modelName: String = "Mivu CarPlay MediaRenderer"
    public var modelNumber: String = "1.0"
    public var serverPort: UInt16 = 7890

    private init() {
        if let savedUUID = UserDefaults.standard.string(forKey: "mivu_upnp_uuid") {
            self.uuid = savedUUID
        } else {
            let newUUID = UUID().uuidString.lowercased()
            UserDefaults.standard.set(newUUID, forKey: "mivu_upnp_uuid")
            self.uuid = newUUID
        }

        let deviceName = UIDevice.current.name
        self.friendlyName = "Mivu (\(deviceName))"
    }

    public var udn: String {
        return "uuid:\(uuid)"
    }

    /// Generates UPnP root device description XML.
    public func deviceDescriptionXML(hostIP _: String) -> String {
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
            <manufacturerURL>https://mivu.app</manufacturerURL>
            <modelDescription>Mivu Local Network &amp; CarPlay Video MediaRenderer</modelDescription>
            <modelName>\(escapeXML(modelName))</modelName>
            <modelNumber>\(modelNumber)</modelNumber>
            <modelURL>https://mivu.app</modelURL>
            <UDN>\(udn)</UDN>
            <serviceList>
              <service>
                <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
                <SCPDURL>/avtransport.xml</SCPDURL>
                <controlURL>/upnp/control/avtransport</controlURL>
                <eventSubURL></eventSubURL>
              </service>
              <service>
                <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
                <SCPDURL>/renderingcontrol.xml</SCPDURL>
                <controlURL>/upnp/control/renderingcontrol</controlURL>
                <eventSubURL></eventSubURL>
              </service>
              <service>
                <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
                <serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>
                <SCPDURL>/connectionmanager.xml</SCPDURL>
                <controlURL>/upnp/control/connectionmanager</controlURL>
                <eventSubURL></eventSubURL>
              </service>
            </serviceList>
          </device>
        </root>
        """
    }

    /// Generates AVTransport:1 Service Control Protocol Description (SCPD).
    public func avTransportSCPD() -> String {
        let instance = input("InstanceID", "A_ARG_TYPE_InstanceID")
        return serviceDescription(actions: [
            ("SetAVTransportURI", [instance, input("CurrentURI", "AVTransportURI"), input("CurrentURIMetaData", "AVTransportURIMetaData")]),
            ("Play", [instance, input("Speed", "TransportPlaySpeed")]),
            ("Pause", [instance]), ("Stop", [instance]),
            ("Seek", [instance, input("Unit", "A_ARG_TYPE_SeekMode"), input("Target", "A_ARG_TYPE_SeekTarget")]),
            ("GetTransportInfo", [instance, output("CurrentTransportState", "TransportState"), output("CurrentTransportStatus", "TransportStatus"), output("CurrentSpeed", "TransportPlaySpeed")]),
            ("GetPositionInfo", [instance, output("Track", "CurrentTrack"), output("TrackDuration", "CurrentTrackDuration"), output("TrackMetaData", "CurrentTrackMetaData"), output("TrackURI", "CurrentTrackURI"), output("RelTime", "RelativeTimePosition"), output("AbsTime", "AbsoluteTimePosition"), output("RelCount", "RelativeCounterPosition"), output("AbsCount", "AbsoluteCounterPosition")]),
            ("GetMediaInfo", [instance, output("NrTracks", "NumberOfTracks"), output("MediaDuration", "CurrentMediaDuration"), output("CurrentURI", "AVTransportURI"), output("CurrentURIMetaData", "AVTransportURIMetaData"), output("NextURI", "NextAVTransportURI"), output("NextURIMetaData", "NextAVTransportURIMetaData"), output("PlayMedium", "PlaybackStorageMedium"), output("RecordMedium", "RecordStorageMedium"), output("WriteStatus", "RecordMediumWriteStatus")]),
            ("GetTransportSettings", [instance, output("PlayMode", "CurrentPlayMode"), output("RecQualityMode", "CurrentRecordQualityMode")])
        ], variables: [
            ("A_ARG_TYPE_InstanceID", "ui4"), ("A_ARG_TYPE_SeekMode", "string"), ("A_ARG_TYPE_SeekTarget", "string"),
            ("AVTransportURI", "uri"), ("AVTransportURIMetaData", "string"),
            ("TransportPlaySpeed", "string"), ("TransportState", "string"), ("TransportStatus", "string"),
            ("CurrentTrack", "ui4"), ("CurrentTrackDuration", "string"), ("CurrentTrackMetaData", "string"), ("CurrentTrackURI", "uri"),
            ("RelativeTimePosition", "string"), ("AbsoluteTimePosition", "string"), ("RelativeCounterPosition", "i4"), ("AbsoluteCounterPosition", "i4"),
            ("NumberOfTracks", "ui4"), ("CurrentMediaDuration", "string"), ("NextAVTransportURI", "uri"), ("NextAVTransportURIMetaData", "string"),
            ("PlaybackStorageMedium", "string"), ("RecordStorageMedium", "string"), ("RecordMediumWriteStatus", "string"),
            ("CurrentPlayMode", "string"), ("CurrentRecordQualityMode", "string")
        ], allowedValues: [
            "A_ARG_TYPE_SeekMode": ["REL_TIME", "ABS_TIME"], "TransportPlaySpeed": ["1"],
            "TransportState": ["STOPPED", "PLAYING", "TRANSITIONING", "PAUSED_PLAYBACK", "NO_MEDIA_PRESENT"],
            "TransportStatus": ["OK", "ERROR_OCCURRED"], "PlaybackStorageMedium": ["NETWORK", "NONE"],
            "RecordStorageMedium": ["NOT_IMPLEMENTED"], "RecordMediumWriteStatus": ["NOT_IMPLEMENTED"],
            "CurrentPlayMode": ["NORMAL"], "CurrentRecordQualityMode": ["NOT_IMPLEMENTED"]
        ])
    }

    /// Generates RenderingControl:1 SCPD.
    public func renderingControlSCPD() -> String {
        let instance = input("InstanceID", "A_ARG_TYPE_InstanceID")
        let channel = input("Channel", "A_ARG_TYPE_Channel")
        return serviceDescription(actions: [
            ("SetVolume", [instance, channel, input("DesiredVolume", "Volume")]),
            ("GetVolume", [instance, channel, output("CurrentVolume", "Volume")]),
            ("SetMute", [instance, channel, input("DesiredMute", "Mute")]),
            ("GetMute", [instance, channel, output("CurrentMute", "Mute")])
        ], variables: [("A_ARG_TYPE_InstanceID", "ui4"), ("A_ARG_TYPE_Channel", "string"), ("Volume", "ui2"), ("Mute", "boolean")],
           allowedValues: ["A_ARG_TYPE_Channel": ["Master"]])
    }

    /// Generates ConnectionManager:1 SCPD.
    public func connectionManagerSCPD() -> String {
        return serviceDescription(actions: [
            ("GetProtocolInfo", [output("Source", "SourceProtocolInfo"), output("Sink", "SinkProtocolInfo")]),
            ("GetCurrentConnectionIDs", [output("ConnectionIDs", "CurrentConnectionIDs")]),
            ("GetCurrentConnectionInfo", [input("ConnectionID", "A_ARG_TYPE_ConnectionID"), output("RcsID", "A_ARG_TYPE_RcsID"), output("AVTransportID", "A_ARG_TYPE_AVTransportID"), output("ProtocolInfo", "A_ARG_TYPE_ProtocolInfo"), output("PeerConnectionManager", "A_ARG_TYPE_ConnectionManager"), output("PeerConnectionID", "A_ARG_TYPE_ConnectionID"), output("Direction", "A_ARG_TYPE_Direction"), output("Status", "A_ARG_TYPE_ConnectionStatus")])
        ], variables: [
            ("SourceProtocolInfo", "string"), ("SinkProtocolInfo", "string"), ("CurrentConnectionIDs", "string"),
            ("A_ARG_TYPE_ConnectionID", "i4"), ("A_ARG_TYPE_RcsID", "i4"), ("A_ARG_TYPE_AVTransportID", "i4"),
            ("A_ARG_TYPE_ProtocolInfo", "string"), ("A_ARG_TYPE_ConnectionManager", "string"),
            ("A_ARG_TYPE_Direction", "string"), ("A_ARG_TYPE_ConnectionStatus", "string")
        ], allowedValues: ["A_ARG_TYPE_Direction": ["Input", "Output"], "A_ARG_TYPE_ConnectionStatus": ["OK", "ContentFormatMismatch", "InsufficientBandwidth", "UnreliableChannel", "Unknown"]])
    }

    private typealias Argument = (name: String, direction: String, variable: String)

    private func input(_ name: String, _ variable: String) -> Argument { (name, "in", variable) }
    private func output(_ name: String, _ variable: String) -> Argument { (name, "out", variable) }

    /// Describe only implemented actions. Eventing is not implemented yet: explicitly
    /// use non-evented variables and an empty eventSubURL instead of advertising a dead endpoint.
    private func serviceDescription(actions: [(String, [Argument])], variables: [(String, String)], allowedValues: [String: [String]] = [:]) -> String {
        let actionXML = actions.map { name, arguments in
            let argumentXML = arguments.map {
                "<argument><name>\($0.name)</name><direction>\($0.direction)</direction><relatedStateVariable>\($0.variable)</relatedStateVariable></argument>"
            }.joined()
            return "<action><name>\(name)</name><argumentList>\(argumentXML)</argumentList></action>"
        }.joined(separator: "\n")
        let variableXML = variables.map { name, type in
            let values = allowedValues[name].map { values in
                "<allowedValueList>" + values.map { "<allowedValue>\(escapeXML($0))</allowedValue>" }.joined() + "</allowedValueList>"
            } ?? ""
            let range = name == "Volume" ? "<allowedValueRange><minimum>0</minimum><maximum>100</maximum><step>1</step></allowedValueRange>" : ""
            return "<stateVariable sendEvents=\"no\"><name>\(name)</name><dataType>\(type)</dataType>\(values)\(range)</stateVariable>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="utf-8"?>
        <scpd xmlns="urn:schemas-upnp-org:service-1-0">
          <specVersion>
            <major>1</major>
            <minor>0</minor>
          </specVersion>
          <actionList>\(actionXML)</actionList>
          <serviceStateTable>\(variableXML)</serviceStateTable>
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
