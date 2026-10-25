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

    @Test("녹음마다 요약을 녹음 순서대로 쌓고, 목소리가 안 잡힌 녹음은 빼며, 정지할 때 함께 넘긴다")
    func recordsEachTake() throws {
        var log = PracticeSessionLog(startedAt: start, language: .korean)
        // 녹음을 시작하기 전에 불리면 무시한다
        log.finishTake(readings: readings(from: 0, count: 10, frequency: { _ in 150 }), duration: 1, target: nil, at: start)
        #expect(log.takes.isEmpty)

        log.beginTake()
        let first = readings(from: 0, count: 300, frequency: { _ in 150 })
        log.add(first)
        log.finishTake(readings: first, duration: 6, target: 140...160, at: start.addingTimeInterval(10))

        log.beginTake()
        let silent = readings(from: 20, count: 300, frequency: { _ in nil })
        log.add(silent)
        log.finishTake(readings: silent, duration: 6, target: 140...160, at: start.addingTimeInterval(30))

        log.beginTake()
        let third = readings(from: 40, count: 300, frequency: { $0 < 150 ? 170 : 190 })
        log.add(third)
        log.finishTake(readings: third, duration: 6, target: 180...220, at: start.addingTimeInterval(50))

        #expect(log.takes.map(\.round) == [1, 3])
        let summary = try #require(log.finish(at: start.addingTimeInterval(60), target: 180...220))
        #expect(summary.takeCount == 3)
        #expect(summary.takes == log.takes)
        let one = summary.takes[0]
        #expect(one.endedAt == start.addingTimeInterval(10))
        #expect(one.pitch.duration == 6)
        #expect(one.pitch.median == 150)
        #expect(one.pitch.target == 140...160)
        #expect(one.pitch.inTargetFraction == 1)
        // 녹음마다 그 녹음을 마친 때의 목표 범위로 잰다
        #expect(summary.takes[1].pitch.median == 180)
        #expect(summary.takes[1].pitch.inTargetFraction == 0.5)
    }

    @Test("녹음 한 줄 표시: 중앙·범위·목표 안 비율 (목표가 없으면 비율은 빼고)")
    func takeNumbersLine() throws {
        let pitch = PitchSummary(duration: 60, voicedSeconds: 25, median: 182.4, p10: 165, p90: 201.2,
                                 target: 160...200, inTargetFraction: 0.72)
        let take = PracticeSessionLog.Take(round: 2, endedAt: start, pitch: pitch)
        #expect(take.numbersLine == "중앙 182 Hz · 165–201 Hz · 목표 안 72%")

        let noTarget = PitchSummary(duration: 60, voicedSeconds: 25, median: 182.4, p10: 165, p90: 201.2,
                                    target: nil, inTargetFraction: nil)
        #expect(PracticeSessionLog.Take(round: 2, endedAt: start, pitch: noTarget).numbersLine == "중앙 182 Hz · 165–201 Hz")
    }

    /// 1번째 녹음은 170 Hz(그때 목표 140~160), 2번째는 190 Hz(목표 180~220), 정지한 때 목표 180~220
    private func twoTakeSummary() throws -> PracticeSessionLog.Summary {
        var log = PracticeSessionLog(startedAt: start, language: .english)
        for (index, frequency, target) in [(0, 170.0, 140.0...160.0), (1, 190.0, 180.0...220.0)] {
            log.beginTake()
            let takeReadings = readings(from: Double(index) * 100, count: 500, frequency: { _ in frequency })
            log.add(takeReadings)
            log.finishTake(readings: takeReadings, duration: 10, target: target,
                           at: start.addingTimeInterval(Double(index + 1) * 40))
        }
        return try #require(log.finish(at: start.addingTimeInterval(90), target: 180...220))
    }

    @Test("연습 요청문: 연습 전체와 녹음마다의 숫자를 넣고, 판정 없이 목표 범위를 기준으로 봐 달라고 쓴다")
    func sessionFeedbackRequest() throws {
        let text = try twoTakeSummary().feedbackRequest()
        for expected in ["[울림 · 보이스 트레이닝 연습 피드백 요청]", "녹음 2번", "말한 언어 영어", "연습 전체",
                         "피치 중앙값: 180 Hz", "내 목표 범위: 180~220 Hz (목표 범위 안 비율 50%)",
                         "- 1번째 녹음 (10초, 목소리 10.0초): 중앙 170 Hz, 범위 170~170 Hz, 목표 범위 안 0% (그때 목표 140~160 Hz)",
                         "- 2번째 녹음 (10초, 목소리 10.0초): 중앙 190 Hz, 범위 190~190 Hz, 목표 범위 안 100%",
                         "녹음마다 어떻게 달라졌는지", "녹음 파일은 보내지 않았어요", "짐작하지 말아 주세요",
                         "성대에 무리가 가지 않는", "높이거나 낮추는 방향은 가정하지 말고",
                         "보이스 트레이닝 앱 ‘울림’이 기기 안에서 직접 잰 값"] {
            #expect(text.contains(expected), "\(expected)")
        }
        // 2번째 녹음은 정지한 때와 목표가 같아 '그때 목표'를 다시 적지 않는다
        #expect(text.components(separatedBy: "그때 목표").count == 2)
        for judgement in ["좋아", "나빠", "개선", "남성", "여성", "점수", "VoicePractice"] {
            #expect(!text.contains(judgement), "\(judgement)")
        }
    }

    @Test("녹음마다 기록이 없는 예전 연습도 요청문을 만들 수 있고, 목표가 없으면 방향을 가정하지 말라고만 쓴다")
    func oldSessionRequest() throws {
        let old = PracticeSessionLog.Summary(
            startedAt: start, endedAt: start.addingTimeInterval(300), takeCount: 3, language: .korean,
            pitch: PitchSummary(duration: 300, voicedSeconds: 80, median: 160, p10: 140, p90: 185,
                                target: nil, inTargetFraction: nil)
        )
        let text = old.feedbackRequest()
        #expect(text.contains("녹음마다 기록이 없는 예전 연습"))
        #expect(text.contains("내 목표 범위: 아직 정하지 않음"))
        #expect(text.contains("높이거나 낮추는 방향은 가정하지 말아 주세요"))
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

    /// 녹음 두 번(170 Hz, 190 Hz)의 요약이 딸린 연습
    private func sessionSummaryWithTakes() throws -> PracticeSessionLog.Summary {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var log = PracticeSessionLog(startedAt: start, language: .korean)
        for (index, frequency) in [(0, 170.0), (1, 190.0)] {
            log.beginTake()
            let readings = (0..<500).map { PitchReading(time: Double(index) * 100 + Double($0) * 0.02, frequency: frequency) }
            log.add(readings)
            log.finishTake(readings: readings, duration: 10, target: 180...220, at: start.addingTimeInterval(Double(index + 1) * 40))
        }
        return try #require(log.finish(at: start.addingTimeInterval(90), target: 180...220))
    }

    @Test("녹음마다 요약은 연습 기록과 함께 남고, 다시 읽으면 녹음 순서대로 같은 값이다")
    func savesTakes() throws {
        let (archive, _) = makeArchive()
        let summary = try sessionSummaryWithTakes()
        try archive.saveSession(summary)

        let session = try #require(try archive.context.fetch(FetchDescriptor<PracticeSession>()).first)
        #expect(try count(PracticeTake.self, in: archive) == 2)
        #expect(session.takes.count == 2)
        #expect(session.summary.takes == summary.takes)
        #expect(session.summary.pitch == summary.pitch)
        #expect(session.summary.takes.map(\.round) == [1, 2])
    }

    @Test("연습 기록을 지우면 녹음마다 요약도 함께 지워진다")
    func deletesTakesWithSession() throws {
        let (archive, _) = makeArchive()
        try archive.saveSession(try sessionSummaryWithTakes())
        try archive.saveSession(try sessionSummary())  // 녹음 요약이 없는 연습 (finishTake를 부르지 않음)
        #expect(try count(PracticeTake.self, in: archive) == 2)

        let withTakes = try #require(try archive.context.fetch(FetchDescriptor<PracticeSession>()).first { !$0.takes.isEmpty })
        try archive.delete(withTakes)
        #expect(try count(PracticeTake.self, in: archive) == 0)
        #expect(try count(PracticeSession.self, in: archive) == 1)
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
        try archive.saveSession(try sessionSummaryWithTakes())
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
        #expect(try count(PracticeTake.self, in: archive) == 0)
        #expect(try count(SavedRecording.self, in: archive) == 0)
        #expect(try count(BaselineRecord.self, in: archive) == 0)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}
