import XCTest
@testable import Vimu

final class SOAPParserTests: XCTestCase {

    func testFormatAndParseUPnPTime() {
        XCTAssertEqual(SOAPParser.formatUPnPTime(0), "00:00:00")
        XCTAssertEqual(SOAPParser.formatUPnPTime(65), "00:01:05")
        XCTAssertEqual(SOAPParser.formatUPnPTime(3665), "01:01:05")

        XCTAssertEqual(SOAPParser.parseUPnPTime("00:00:00"), 0)
        XCTAssertEqual(SOAPParser.parseUPnPTime("00:01:05"), 65)
        XCTAssertEqual(SOAPParser.parseUPnPTime("01:01:05"), 3665)
    }

    func testExtractTitleFromDIDLLite() {
        let didl = """
        &lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/"&gt;
          &lt;item id="1" parentID="0" restricted="1"&gt;
            &lt;dc:title&gt;Sample Video Title&lt;/dc:title&gt;
            &lt;res protocolInfo="http-get:*:video/mp4:*"&gt;http://192.168.1.100:8000/video.mp4&lt;/res&gt;
          &lt;/item&gt;
        &lt;/DIDL-Lite&gt;
        """
        let title = SOAPParser.extractTitleFromDIDLLite(didl)
        XCTAssertEqual(title, "Sample Video Title")
    }

    func testParseSOAPAction() {
        let soapXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
              <InstanceID>0</InstanceID>
              <CurrentURI>http://192.168.1.50:8080/movie.mp4</CurrentURI>
            </u:SetAVTransportURI>
          </s:Body>
        </s:Envelope>
        """
        guard let data = soapXML.data(using: .utf8) else {
            XCTFail("Failed to convert string to data")
            return
        }

        let action = SOAPParser.parseAction(bodyData: data, soapActionHeader: "\"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionName, "SetAVTransportURI")
        XCTAssertEqual(action?.parameters["CurrentURI"], "http://192.168.1.50:8080/movie.mp4")
    }

    func testParseRenderingControlAction() {
        let soapXML = """
        <?xml version="1.0" encoding="utf-8"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
          <s:Body>
            <u:SetVolume xmlns:u="urn:schemas-upnp-org:service:RenderingControl:1">
              <InstanceID>0</InstanceID>
              <Channel>Master</Channel>
              <DesiredVolume>75</DesiredVolume>
            </u:SetVolume>
          </s:Body>
        </s:Envelope>
        """
        guard let data = soapXML.data(using: .utf8) else {
            XCTFail("Failed to convert string to data")
            return
        }

        let action = SOAPParser.parseAction(bodyData: data, soapActionHeader: "\"urn:schemas-upnp-org:service:RenderingControl:1#SetVolume\"")
        XCTAssertNotNil(action)
        XCTAssertEqual(action?.actionName, "SetVolume")
        XCTAssertEqual(action?.parameters["DesiredVolume"], "75")
    }

    func testDeepLinkParsing() {
        let url = URL(string: "vimu://play?url=https%3A%2F%2Fexample.com%2Fstream.m3u8&title=TestStream")!
        let item = URLSource.parseDeepLink(url: url)
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.title, "TestStream")
        XCTAssertEqual(item?.url.absoluteString, "https://example.com/stream.m3u8")
    }

    func testWebRemoteTemplateRender() {
        let html = WebRemoteTemplate.render(ip: "192.168.1.88", port: 7890, friendlyName: "Vimu Car")
        XCTAssertTrue(html.contains("Vimu 网页遥控器"))
        XCTAssertTrue(html.contains("Vimu Car"))
        XCTAssertTrue(html.contains("/api/play"))
    }
}
