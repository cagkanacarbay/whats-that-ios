import XCTest
@testable import WhatsThatDomain

final class DiscoveryAnalysisParserTests: XCTestCase {
    func testParseExtractsMetadataAndNarrative() {
        let parser = DiscoveryAnalysisParser()
        let rawStream = """
        status
        === USER RESPONSE ===
        ## Redwood Sentinel

        An ancient tree stands tall along the ridge, bathing in coastal fog.

        ### metadata_json
        {"title":"Redwood Sentinel","shortDescription":"A centuries-old coast redwood."}
        """

        guard let content = parser.parse(rawStream) else {
            return XCTFail("Expected parsed content")
        }

        XCTAssertEqual(content.metadata?.title, "Redwood Sentinel")
        XCTAssertEqual(content.metadata?.shortDescription, "A centuries-old coast redwood.")
        XCTAssertTrue(content.markdown.contains("## Redwood Sentinel"))
        XCTAssertFalse(content.markdown.contains("metadata_json"))
        XCTAssertFalse(content.markdown.contains("shortDescription"))
    }

    func testParseIgnoresEmptyPayload() {
        let parser = DiscoveryAnalysisParser()
        XCTAssertNil(parser.parse(""))
        XCTAssertNil(parser.parse("   "))
    }

    func testParseExtractsInlineMetadataJSONWithoutHeading() {
        let parser = DiscoveryAnalysisParser()
        let rawStream = """
        === USER RESPONSE ===
        ## Goðafoss Waterfall

        {"title":"Goðafoss Waterfall","shortDescription":"Iconic waterfall in northern Iceland."}

        The waterfall spans the width of the Skjálfandafljót river.
        """

        guard let content = parser.parse(rawStream) else {
            return XCTFail("Expected parsed content")
        }

        XCTAssertEqual(content.metadata?.title, "Goðafoss Waterfall")
        XCTAssertEqual(content.metadata?.shortDescription, "Iconic waterfall in northern Iceland.")
        XCTAssertFalse(content.markdown.contains("shortDescription"))
        XCTAssertFalse(content.markdown.contains("Goðafoss Waterfall\",\"shortDescription"))
    }
}
