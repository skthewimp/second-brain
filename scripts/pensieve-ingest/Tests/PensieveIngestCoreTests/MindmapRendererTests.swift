import XCTest
@testable import PensieveIngestCore

final class MindmapRendererTests: XCTestCase {
    func testRendersInlineDataAndContainsD3CDN() throws {
        let state = MindmapState(version: 1, lastUpdated: "2026-04-25",
            root: MindmapNode(id: "root", label: "Brain", noteCount: 0,
                              importance: 10, summary: "", sourcePages: [],
                              children: [
                MindmapNode(id: "career", label: "Career", noteCount: 12,
                            importance: 9, summary: "", sourcePages: [], children: [])
            ]))
        let insights = [Insight(kind: .tooDeep, nodeId: "career", message: "test")]
        let html = MindmapRenderer.render(state: state, insights: insights)

        XCTAssertTrue(html.contains("d3js.org/d3.v7"))
        XCTAssertTrue(html.contains("\"id\":\"career\""))
        XCTAssertTrue(html.contains("\"kind\":\"tooDeep\""))
        XCTAssertTrue(html.contains("2026-04-25"))
    }
}
