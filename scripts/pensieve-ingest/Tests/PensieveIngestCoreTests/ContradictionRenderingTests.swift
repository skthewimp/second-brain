import XCTest
@testable import PensieveIngestCore

final class ContradictionRenderingTests: XCTestCase {

    func testExtractedRendersWithSourceLinks() {
        let c = IngestionPatch.Contradiction(
            kind: .extracted,
            topic: "Career direction",
            before: .init(date: "2026-03-12", quote: "I want to go full-time consulting", sourceNoteId: "2026-03-12_0824"),
            now: .init(date: "2026-04-10", quote: "I want a salaried job", sourceNoteId: "2026-04-10_0905"),
            nature: "reversal",
            relatedThemes: ["career"]
        )
        let out = VaultWriter.renderContradiction(c)
        XCTAssertTrue(out.contains("> [!extracted] 2026-04-10 — Career direction"))
        XCTAssertTrue(out.contains("[[2026-03-12_0824]]"))
        XCTAssertTrue(out.contains("[[2026-04-10_0905]]"))
        XCTAssertTrue(out.contains("> **Nature**: reversal"))
        XCTAssertTrue(out.contains("> **Related**: [[career]]"))
    }

    func testExtractedDowngradesToInferredWhenSourceMissing() {
        let c = IngestionPatch.Contradiction(
            kind: .extracted,
            topic: "Anxious vs confident",
            before: .init(date: "2026-03-12", quote: "I'm anxious about money", sourceNoteId: nil),
            now: .init(date: "2026-04-10", quote: "Money feels fine now", sourceNoteId: "2026-04-10_0905"),
            nature: "softening",
            relatedThemes: nil
        )
        let out = VaultWriter.renderContradiction(c)
        XCTAssertTrue(out.contains("> [!inferred]"))
        XCTAssertFalse(out.contains("> [!extracted]"))
    }

    func testAmbiguousRendersWithoutOptionalFields() {
        let c = IngestionPatch.Contradiction(
            kind: .ambiguous,
            topic: "Autonomy vs structure",
            before: .init(date: "2026-03-12", quote: "I want freedom", sourceNoteId: nil),
            now: .init(date: "2026-04-10", quote: "I want structure", sourceNoteId: nil),
            nature: nil,
            relatedThemes: nil
        )
        let out = VaultWriter.renderContradiction(c)
        XCTAssertTrue(out.contains("> [!ambiguous] 2026-04-10 — Autonomy vs structure"))
        XCTAssertFalse(out.contains("Nature"))
        XCTAssertFalse(out.contains("Related"))
        XCTAssertFalse(out.contains("[["))
    }
}
