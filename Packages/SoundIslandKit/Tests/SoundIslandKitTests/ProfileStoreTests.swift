import XCTest
import SwiftData
import Curriculum
import StudioModel
@testable import ProfileStore

@MainActor
final class ProfileStoreTests: XCTestCase {
    private func makeStore() throws -> ProfileStore {
        ProfileStore(container: try ProfileStore.makeContainer(inMemory: true))
    }

    private func sampleSnapshot() -> ProfileSnapshot {
        var s = ProfileSnapshot(nickname: "Robin", avatar: "owl", ageBand: .makers)
        s.sessionIndex = 7
        s.quietMode = true
        s.bestStars = ["crab_tap": 3, "chord_chef": 1]
        s.unlockedTools = [.beatBox, .chordPads]
        var p = SkillProgress(skillID: "rhythm.pulse")
        p.currentTier = 2
        p.recentResults = [true, false, true]
        p.firstMasteredSession = 5
        s.progress = [p.skillID: p]
        s.song.setTempo(110)
        return s
    }

    func testSnapshotRoundTrip() throws {
        let store = try makeStore()
        let expected = sampleSnapshot()
        let profile = try store.addProfile(expected)
        XCTAssertEqual(store.snapshot(of: profile), expected)
        XCTAssertEqual(profile.skills.count, 1)
    }

    func testWriteUpdatesAndRemovesSkillRows() throws {
        let store = try makeStore()
        let profile = try store.addProfile(sampleSnapshot())
        var s = store.snapshot(of: profile)
        s.progress["rhythm.pulse"]?.currentTier = 3
        var other = SkillProgress(skillID: "harmony.triads")
        other.attempts = 4
        s.progress[other.skillID] = other
        try store.write(s, to: profile)
        XCTAssertEqual(store.snapshot(of: profile).progress["rhythm.pulse"]?.currentTier, 3)
        XCTAssertEqual(profile.skills.count, 2)

        s.progress.removeValue(forKey: "rhythm.pulse")
        try store.write(s, to: profile)
        XCTAssertEqual(Set(store.snapshot(of: profile).progress.keys), ["harmony.triads"])
    }

    func testAtMostFourProfilesInCreationOrder() throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_000)
        for (i, name) in ["A", "B", "C", "D"].enumerated() {
            try store.addProfile(ProfileSnapshot(nickname: name), createdAt: base.addingTimeInterval(Double(i)))
        }
        XCTAssertFalse(try store.canAddProfile())
        XCTAssertThrowsError(try store.addProfile(ProfileSnapshot(nickname: "E"))) {
            XCTAssertEqual($0 as? ProfileStoreError, .tooManyProfiles)
        }
        XCTAssertEqual(try store.allProfiles().map(\.nickname), ["A", "B", "C", "D"])
    }

    func testDeleteCascadesButKeepsLastProfile() throws {
        let store = try makeStore()
        let a = try store.addProfile(sampleSnapshot())
        let b = try store.addProfile(ProfileSnapshot(nickname: "Sam"))
        try store.delete(a)
        XCTAssertEqual(try store.context.fetchCount(FetchDescriptor<SkillProgressRecord>()), 0)
        XCTAssertThrowsError(try store.delete(b)) { XCTAssertEqual($0 as? ProfileStoreError, .lastProfile) }
        XCTAssertNotNil(try store.profile(id: b.id))
    }

    func testLegacyJSONMigratesOnceAndKeepsBackup() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("profile.json")
        let expected = sampleSnapshot()
        try JSONEncoder().encode(expected).write(to: url)

        let store = try makeStore()
        let migrated = try XCTUnwrap(store.migrateLegacyJSON(at: url))
        XCTAssertEqual(store.snapshot(of: migrated), expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("profile.migrated.json").path))

        try JSONEncoder().encode(sampleSnapshot()).write(to: url)
        XCTAssertNil(try store.migrateLegacyJSON(at: url), "never imports into a non-empty store")
        XCTAssertEqual(try store.allProfiles().count, 1)
    }

    func testEnsureProfileCreatesDefaultOnce() throws {
        let store = try makeStore()
        let first = try store.ensureProfile()
        XCTAssertEqual(first.nickname, "Player 1")
        XCTAssertEqual(try store.ensureProfile().id, first.id)
    }
}
