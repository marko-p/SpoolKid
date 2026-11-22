import Testing
import Foundation
@testable import SpoolKid

struct WebSpoolParserServiceTests {

    @Test func parserDoesNotEmitWorkflowTraceEvents() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        func decodeEvents(_ json: String) throws -> [WorkflowTraceEvent] {
            let data = try #require(json.data(using: .utf8))
            return try decoder.decode([WorkflowTraceEvent].self, from: data)
        }

        func isWebParserRelated(_ event: WorkflowTraceEvent) -> Bool {
            event.path.hasPrefix("web")
                || (
                    event.path == "hub"
                        && (
                            event.step.hasPrefix("resolve.web")
                                || event.step.hasPrefix("web-challenge")
                        )
                )
        }

        let beforeEvents = try decodeEvents(WorkflowTraceStore.shared.exportJSONString())

        let html = """
        <html>
          <head>
            <title>Fiberon ASA-CF08 by Polymaker</title>
            <meta property=\"og:title\" content=\"Fiberon ASA-CF08 by Polymaker\" />
          </head>
          <body>
            <h1>Fiberon ASA-CF08</h1>
            <p>Printing temperature: 260-300 C</p>
            <p>Bed temperature: 80-100 C</p>
          </body>
        </html>
        """

        let url = try #require(URL(string: "https://example-filament-store.com/products/fiberon-asa-cf08"))
        _ = try WebSpoolParserService.shared.parse(html: html, url: url)

        let afterEvents = try decodeEvents(WorkflowTraceStore.shared.exportJSONString())

        let beforeWebParserEvents = beforeEvents.filter(isWebParserRelated).count
        let afterWebParserEvents = afterEvents.filter(isWebParserRelated).count
        #expect(afterWebParserEvents == beforeWebParserEvents)
    }

    @Test func genericParserExtractsMaterialBrandAndTemps() throws {
        let html = """
        <html>
          <head>
            <title>Fiberon ASA-CF08 by Polymaker</title>
            <meta property=\"og:title\" content=\"Fiberon ASA-CF08 by Polymaker\" />
          </head>
          <body>
            <h1>Fiberon ASA-CF08</h1>
            <p>Printing temperature: 260-300 C</p>
            <p>Bed temperature: 80-100 C</p>
          </body>
        </html>
        """

        let url = try #require(URL(string: "https://example-filament-store.com/products/fiberon-asa-cf08"))
        let parsed = try WebSpoolParserService.shared.parse(html: html, url: url)

        #expect(parsed.material == "ASA-CF08")
        #expect(parsed.brand == "Polymaker")
        #expect(parsed.minNozzleTemp == 260)
        #expect(parsed.maxNozzleTemp == 300)
        #expect(parsed.minBedTemp == 80)
        #expect(parsed.maxBedTemp == 100)
    }

    @Test func polymakerLinkAliasParsesAsPolymaker() throws {
        let html = """
        <html>
          <head><title>Some landing page</title></head>
          <body><h1>Scan redirect</h1></body>
        </html>
        """

        let url = try #require(URL(string: "https://polymaker.link/qr/fiberon/ASA-CF08"))
        let parsed = try WebSpoolParserService.shared.parse(html: html, url: url)

        #expect(parsed.material == "ASA")
        #expect(parsed.subtype == "ASA-CF08")
        #expect(parsed.brand == "Polymaker")
        #expect(parsed.name?.contains("Fiberon") == true)
    }
}
