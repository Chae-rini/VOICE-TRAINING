import Foundation
import SwiftData
import Testing
@testable import VoicePractice

@MainActor
struct PracticeSessionLogTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// `from` [s]부터 0.02초 간격의 피치 점 `count`개. nil은 무음.
    private func readings(from time: TimeInterval, count: Int, frequency: (Int) -> Double?) -> [PitchReading] {
        (0..<count).map { PitchReading(time: time + Double($0) * 0.02, frequency: frequency($0)) }
    }

    @Test("녹음 두 번을 하나로 모으고, 녹음 사이의 빈 시간은 목소리로 세지 않는다")
    func combinesTakes() throws {
        var log = PracticeSessionLog(startedAt: start, language: .english)
        log.beginTake()
        log.add(readings(from: 100, count: 300, frequency: { _ in 150 }))  // 6초 동안 150 Hz
        log.beginTake()
        log.add(readings(from: 200, count: 300, frequency: { _ in 250 }))  // 100초 뒤 6초 동안 250 Hz

        let summary = try #require(log.finish(at: start.addingTimeInterval(120), target: 140...160))
        #expect(summary.takeCount == 2)
        #expect(summary.language == .english)
        #expect(summary.startedAt == start)
        #expect(summary.pitch.duration == 120)
        #expect(abs(summary.pitch.voicedSeconds - 2 * 299 * 0.02) < 1e-9)  // 첫 점은 앞 점이 없어 0
        #expect(abs(summary.pitch.median - 200) < 1e-9)
        #expect(summary.pitch.p10 == 150)
        #expect(summary.pitch.p90 == 250)
        #expect(summary.pitch.target == 140...160)
        #expect(summary.pitch.inTargetFraction == 0.5)
    }

    @Test("녹음 중에 잠깐 쉰 시간도 목소리로 세지 않는다 (점 사이가 0.1초 넘게 벌어지면 0.1초까지만)")
    func capsGaps() {
        var log = PracticeSessionLog(startedAt: start, language: .korean)
        log.beginTake()
        log.add([
            PitchReading(time: 10.00, frequency: 200),
            PitchReading(time: 10.02, frequency: 200),
            PitchReading(time: 10.04, frequency: nil),
            PitchReading(time: 12.04, frequency: 200),  // 무음 점 뒤 2초 만에 다시 목소리
        ])
        #expect(abs(log.voicedSeconds - (0.02 + 0.1)) < 1e-9)
        #expect(log.voiced.count == 3)
    }

    @Test("30초보다 짧은 연습이나 목소리가 5초보다 짧게 잡힌 연습은 남기지 않는다")
    func skipsShortSessions() {
        var log = PracticeSessionLog(startedAt: start, language: .korean)
        log.beginTake()
        log.add(readings(from: 0, count: 500, frequency: { _ in 200 }))  // 약 10초
        #expect(log.finish(at: start.addingTimeInterval(20), target: nil) == nil)
        #expect(log.finish(at: start.addingTimeInterval(30), target: nil) != nil)

        var quiet = PracticeSessionLog(startedAt: start, language: .korean)
        quiet.beginTake()
        quiet.add(readings(from: 0, count: 3000, frequency: { $0 < 200 ? 200 : nil }))  // 60초 중 4초만 목소리
        #expect(quiet.finish(at: start.addingTimeInterval(60), target: nil) == nil)
    }

    @Test("목표 범위를 정하지 않았으면 목표 범위 안 비율도 없다")
    func noTarget() throws {
        var log = PracticeSessionLog(startedAt: start, language: .japanese)
        log.beginTake()
        log.add(readings(from: 0, count: 500, frequency: { _ in 180 }))
        let summary = try #require(log.finish(at: start.addingTimeInterval(45), target: nil))
        #expect(summary.pitch.target == nil)
        #expect(summary.pitch.inTargetFraction == nil)
        #expect(summary.takeCount == 1)
    }
}

@MainActor
struct PracticeArchiveTests {
    /// 메모리 저장소와 임시 폴더를 쓰는 저장소 (앱의 실제 기록은 건드리지 않음)
    private func makeArchive() -> (PracticeArchive, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)")
        return (PracticeArchive(inMemory: true, recordingsDirectory: directory), directory)
    }

    private func count<T: PersistentModel>(_ type: T.Type, in archive: PracticeArchive) throws -> Int {
        try archive.context.fetchCount(FetchDescriptor<T>())
    }

    private func sessionSummary() throws -> PracticeSessionLog.Summary {
        var log = PracticeSessionLog(startedAt: Date(timeIntervalSince1970: 1_800_000_000), language: .english)
        log.beginTake()
        log.add((0..<500).map { PitchReading(time: Double($0) * 0.02, frequency: 190) })
        return try #require(log.finish(at: Date(timeIntervalSince1970: 1_800_000_090), target: 180...220))
    }

    @Test("연습 요약을 남기면 같은 값으로 다시 읽힌다")
    func savesSession() throws {
        let (archive, _) = makeArchive()
        try archive.saveSession(try sessionSummary())

        let sessions = try archive.context.fetch(FetchDescriptor<PracticeSession>())
        let session = try #require(sessions.first)
        #expect(sessions.count == 1)
        #expect(session.practiceSeconds == 90)
        #expect(session.takeCount == 1)
        #expect(session.medianHz == 190)
        #expect(session.targetLowerHz == 180)
        #expect(session.targetUpperHz == 220)
        #expect(session.inTargetFraction == 1)
        #expect(session.language == .english)
    }

    @Test("내 목소리 재기와 모음 재기는 잴 때마다 이력이 하나씩 쌓인다")
    func savesMeasurements() throws {
        let (archive, _) = makeArchive()
        try archive.saveBaseline(VoiceBaseline(median: 150, low: 130, high: 175))
        try archive.saveBaseline(VoiceBaseline(median: 160, low: 140, high: 185))
        let entry = VowelMap.Entry(f1: 750, f2: 1300, f1Spread: 730...770, f2Spread: 1280...1330,
                                   isF1Uncertain: false, measuredAt: Date(timeIntervalSince1970: 1_800_000_000))
        try archive.saveVowel(entry, for: .a)

        #expect(try count(BaselineRecord.self, in: archive) == 2)
        let vowel = try #require(try archive.context.fetch(FetchDescriptor<VowelRecord>()).first)
        #expect(vowel.vowel == "아")
        #expect(vowel.f1 == 750)
        #expect(vowel.f2Low == 1280)
        #expect(vowel.f2High == 1330)
        #expect(vowel.measuredAt == entry.measuredAt)
    }

    @Test("남긴 녹음은 m4a로 저장되고, 백업에서 빠지며, 다시 읽어 재면 같은 높이가 나온다")
    func savesRecording() async throws {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = Signal.sine(200, sampleRate: 48_000, count: 48_000 * 3)
        let summary = try #require(PitchSummary(
            readings: AudioFileAnalyzer.pitchReadings(samples, sampleRate: 48_000), duration: 3, target: nil
        ))

        let recording = try await archive.saveRecording(
            samples: samples, sampleRate: 48_000, summary: summary, title: "", memo: "발표 연습",
            language: .japanese, recordedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let url = archive.fileURL(for: recording)
        #expect(url.pathExtension == "m4a")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        #expect(recording.memo == "발표 연습")
        #expect(recording.language == .japanese)
        #expect(abs(recording.medianHz - 200) < 1)

        // 압축해도 높이는 그대로 잴 수 있다.
        let reread = try AudioFileAnalyzer.analyze(url: url)
        let rereadSummary = try #require(PitchSummary(readings: reread.readings, duration: reread.duration, target: nil))
        #expect(abs(rereadSummary.median - 200) < 1)
        #expect(abs(reread.duration - 3) < 0.1)

        try archive.delete(recording)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try count(SavedRecording.self, in: archive) == 0)
    }

    @Test("연습 기록과 기준 이력은 하나씩 지울 수 있다")
    func deletesOne() throws {
        let (archive, _) = makeArchive()
        try archive.saveSession(try sessionSummary())
        try archive.saveBaseline(VoiceBaseline(median: 150, low: 130, high: 175))
        try archive.saveBaseline(VoiceBaseline(median: 160, low: 140, high: 185))

        try archive.delete(try #require(try archive.context.fetch(FetchDescriptor<PracticeSession>()).first))
        try archive.delete(try #require(try archive.context.fetch(FetchDescriptor<BaselineRecord>()).first))
        #expect(try count(PracticeSession.self, in: archive) == 0)
        #expect(try count(BaselineRecord.self, in: archive) == 1)
    }

    @Test("남긴 녹음의 화면 이름: 불러온 파일은 파일 이름, 앱에서 녹음한 것은 날짜")
    func displayTitle() throws {
        let summary = try #require(PitchSummary(voiced: [150, 160, 170], voicedSeconds: 3, duration: 5, target: 140...180))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let imported = SavedRecording(summary: summary, title: "음성 메모 12", memo: "", fileName: "a.m4a",
                                      language: .korean, recordedAt: date)
        let live = SavedRecording(summary: summary, title: "", memo: "", fileName: "b.m4a", language: .korean, recordedAt: date)
        #expect(imported.displayTitle == "음성 메모 12")
        #expect(live.displayTitle.hasSuffix(" 녹음"))
        #expect(live.displayTitle != " 녹음")
        #expect(live.target == 140...180)
    }

    @Test("모든 기록 지우기: 숫자 기록과 녹음 파일이 모두 사라진다")
    func deletesAll() async throws {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        try archive.saveSession(try sessionSummary())
        try archive.saveBaseline(VoiceBaseline(median: 150, low: 130, high: 175))
        let samples = Signal.sine(150, sampleRate: 48_000, count: 48_000)
        let summary = try #require(PitchSummary(
            readings: AudioFileAnalyzer.pitchReadings(samples, sampleRate: 48_000), duration: 1, target: nil
        ))
        try await archive.saveRecording(samples: samples, sampleRate: 48_000, summary: summary, title: "음성 메모",
                                        memo: "", language: .korean, recordedAt: .now)
        #expect(FileManager.default.fileExists(atPath: directory.path))

        try archive.deleteAll()
        #expect(try count(PracticeSession.self, in: archive) == 0)
        #expect(try count(SavedRecording.self, in: archive) == 0)
        #expect(try count(BaselineRecord.self, in: archive) == 0)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
