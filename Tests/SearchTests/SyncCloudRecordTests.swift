import CloudKit
import XCTest
@testable import Search

/// A Mac's sync file through a CloudKit record and back (SyncCloud.swift):
/// what it says goes in the record's encrypted fields, never in the clear,
/// and a file too large for a record goes as an asset. No network: records
/// are only made and read here. Two Macs syncing through records are
/// Tests/sync_icloud.py.
@MainActor
final class SyncCloudRecordTests: XCTestCase {
    private let zone = CKRecordZone.ID(zoneName: SyncCloud.zoneName, ownerName: CKCurrentUserDefaultName)

    private func file(items count: Int, size: Int = 10) -> SyncFile {
        var items: [String: SyncEntry] = [:]
        for n in 0..<count {
            items["pin:\(n)"] = SyncEntry(v: String(repeating: "x", count: size), t: Double(n), d: "mac-a")
        }
        return SyncFile(format: SyncMerge.format, device: "mac-a", name: "Edin's MacBook", scope: "app", written: 42, items: items)
    }

    func testAFileComesBackFromItsRecord() throws {
        let made = file(items: 5)
        var spare: URL?
        let record = try SyncCloudKit.record(for: made, name: "app.mac-a", zone: zone, spare: &spare)
        XCTAssertNil(spare, "a small file goes in the record itself")
        XCTAssertEqual(SyncCloudKit.file(from: record), made)
        XCTAssertEqual(record.recordID.recordName, "app.mac-a")
        XCTAssertEqual(record.recordType, SyncCloud.recordType)
    }

    func testWhatItSaysIsEncrypted() throws {
        var spare: URL?
        let record = try SyncCloudKit.record(for: file(items: 3), name: "app.mac-a", zone: zone, spare: &spare)
        // Only where it is kept and whose it is are in the clear: the file
        // and the Mac's name are there only as encrypted values.
        XCTAssertNotNil(record["scope"] as? String)
        XCTAssertNotNil(record.encryptedValues["data"] as? Data)
        XCTAssertEqual(record.encryptedValues["name"] as? String, "Edin's MacBook")
        XCTAssertNil(record["data"])
        XCTAssertNil(record["name"])
    }

    func testALargeFileGoesAsAnAsset() throws {
        let made = file(items: 400, size: 3000)
        var spare: URL?
        let record = try SyncCloudKit.record(for: made, name: "app.mac-a", zone: zone, spare: &spare)
        defer { if let spare { try? FileManager.default.removeItem(at: spare) } }
        XCTAssertNotNil(spare)
        XCTAssertNotNil(record["asset"] as? CKAsset)
        XCTAssertNil(record.encryptedValues["data"])
        XCTAssertEqual(SyncCloudKit.file(from: record), made)
    }

    func testARecordOfAnotherFormatIsPassedOver() throws {
        var spare: URL?
        let record = try SyncCloudKit.record(for: file(items: 1), name: "app.mac-a", zone: zone, spare: &spare)
        record["scope"] = "profile-elsewhere" as NSString
        XCTAssertNil(SyncCloudKit.file(from: record), "a file in the wrong scope is not read")
    }

    func testProblemsAreSaidPlainly() {
        XCTAssertEqual(SyncCloud.describe(SyncCloud.Problem.signedOut), "Sign in to iCloud in System Settings")
        XCTAssertEqual(SyncCloud.describe(CKError(.quotaExceeded)), "iCloud is full")
        XCTAssertTrue(SyncCloud.describe(CKError(.networkUnavailable)).hasPrefix("Offline"))
        XCTAssertNil(SyncCloud.retryAfter(CKError(.quotaExceeded)))
    }
}
