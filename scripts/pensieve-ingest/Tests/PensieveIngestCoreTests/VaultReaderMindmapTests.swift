import XCTest
@testable import PensieveIngestCore

final class VaultReaderMindmapTests: XCTestCase {
    func testLoadsExistingMindmap() throws {
        let tmp = try makeTempVaultWithMindmap()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let reader = VaultReader(vaultURL: tmp)
        let state = try reader.loadMindmapState()
        XCTAssertEqual(state?.root.children.first?.id, "career")
    }

    func testReturnsNilWhenMissing() throws {
        let tmp = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let reader = VaultReader(vaultURL: tmp)
        let state = try reader.loadMindmapState()
        XCTAssertNil(state)
    }

    private func makeTempVault() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent("wiki"), withIntermediateDirectories: true)
        return tmp
    }

    private func makeTempVaultWithMindmap() throws -> URL {
        let tmp = try makeTempVault()
        guard let src = Bundle.module.url(
            forResource: "sample-mindmap", withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            fatalError("sample-mindmap.json fixture missing — check Package.swift resources directive")
        }
        let dst = tmp.appendingPathComponent("wiki/mindmap.json")
        try FileManager.default.copyItem(at: src, to: dst)
        return tmp
    }
}
