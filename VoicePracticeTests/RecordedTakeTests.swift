import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import VoicePractice

/// 외부 코드 리뷰에서 나온 버그 세 개의 재현 테스트 (2026-10-25).
@MainActor
struct RecordedTakeTests {
    private let sampleRate = 48_000.0

    private func sine(_ frequency: Double, seconds: Double) -> [Float] {
        Signal.sine(frequency, sampleRate: sampleRate, count: Int(sampleRate * seconds))
    }

    /// 연습 녹음 한 번을 흉내 낸다: 들어온 소리를 `keepSeconds`초만 남기는 녹음 통과, 같은 소리로 잰 피치 점.
    /// `startTime` [s]: 소리가 들어오기 시작한 시각. 실제 앱처럼 그래프용 기록은 녹음을 시작할 때 새로 만든다.
    @discardableResult
    private func recordTake(_ samples: [Float], keepSeconds: TimeInterval, startTime: TimeInterval = 0,
                            into timeline: inout RecordingTimeline) throws -> RecordedTake {
        timeline.beginRecording(keepSeconds: keepSeconds)
        let readings = AudioFileAnalyzer.pitchReadings(samples, sampleRate: sampleRate).map {
            PitchReading(time: $0.time + startTime, frequency: $0.frequency, formants: $0.formants)
        }
        timeline.receive(readings, isMeasuring: false)
        let recorder = TakeRecorder(sampleRate: sampleRate, keepSeconds: keepSeconds)
        recorder.append(samples, at: startTime)
        let playback = try #require(recorder.makePlaybackBuffer())
        return timeline.keepTake(buffer: playback.buffer, startTime: try #require(recorder.startTime),
                                 playbackGain: playback.gain, language: .korean)
    }

    // MARK: - 버그 ① 요약 구간이 실제 녹음보다 길다

    @Test("버그 ①: 최근 10초만 남긴 녹음의 요약은 그 10초만 반영한다 (앞 10초 100 Hz, 뒤 10초 200 Hz)")
    func summaryCoversOnlyKeptSound() throws {
        var timeline = RecordingTimeline()
        let take = try recordTake(sine(100, seconds: 10) + sine(200, seconds: 10), keepSeconds: 10, into: &timeline)
        #expect(abs(take.startTime - 10) < 1e-9)
        #expect(abs(take.duration - 10) < 1e-9)

        let summary = try #require(timeline.lastTakeSummary(target: 190...210))
        #expect(abs(summary.median - 200) < 1)
        #expect(abs(summary.p10 - 200) < 2, "앞의 100 Hz가 섞이면 아래 10%가 100 Hz 쪽으로 내려간다: \(summary.p10)")
        #expect((summary.inTargetFraction ?? 0) > 0.99)
        #expect(summary.voicedSeconds < 10.1)
        // 묶음 안의 점은 모두 소리 구간 안에 있다
        #expect(take.readings.allSatisfy { $0.time >= take.startTime && $0.time <= take.endTime })
    }

    // MARK: - 버그 ② 기준·모음 측정이 마지막 녹음의 수치를 덮어쓴다

    @Test("버그 ②: 녹음 A 뒤에 내 목소리 재기 B를 해도, A의 요약·공유 요청문·저장·다시 듣기 그래프는 A의 수치다")
    func measuringDoesNotOverwriteLastTake() async throws {
        var timeline = RecordingTimeline()
        // A: 연습 녹음 10초, 150 Hz
        let take = try recordTake(sine(150, seconds: 10), keepSeconds: 10, into: &timeline)

        // B: A가 끝나고 20초 뒤 내 목소리 재기 10초, 250 Hz
        timeline.beginRecording(keepSeconds: 10)
        let measuring = AudioFileAnalyzer.pitchReadings(sine(250, seconds: 10), sampleRate: sampleRate).map {
            PitchReading(time: $0.time + 30, frequency: $0.frequency, formants: $0.formants)
        }
        timeline.receive(measuring, isMeasuring: true)
        let measured = timeline.finishMeasuring()
        guard case .measured(let baseline) = VoiceBaseline.measure(measured) else {
            Issue.record("재기 결과가 없다")
            return
        }
        #expect(abs(baseline.median - 250) < 1)

        // 요약 카드
        let summary = try #require(timeline.lastTakeSummary(target: 140...160))
        #expect(abs(summary.median - 150) < 1, "A의 소리인데 B의 수치가 나왔다: \(summary.median)")
        #expect((summary.inTargetFraction ?? 0) > 0.99)
        // AI 공유 요청문
        for includesAudio in [false, true] {
            let request = summary.feedbackRequest(title: take.title, includesAudio: includesAudio)
            #expect(request.contains("피치 중앙값: 150 Hz"))
            #expect(!request.contains("250 Hz"))
        }
        // 기록에 남기기 (AudioInputManager.saveLastTake와 같은 순서: 묶음의 소리 + 묶음의 요약)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("take-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = PracticeArchive(inMemory: true, recordingsDirectory: directory)
        let record = try await archive.saveRecording(
            samples: try #require(take.originalSamples), sampleRate: sampleRate, summary: summary,
            title: take.archiveTitle, memo: "", language: .korean, recordedAt: take.recordedAt
        )
        #expect(abs(record.medianHz - 150) < 1)
        // 다시 듣기 그래프
        let shown = timeline.display.readings.compactMap(\.frequency)
        #expect(!shown.isEmpty)
        #expect(shown.allSatisfy { abs($0 - 150) < 5 }, "재기를 마친 뒤 그래프가 A로 돌아오지 않았다")
    }

    @Test("버그 ②: 재기를 중간에 멈춰도 마지막 녹음의 요약과 그래프는 그대로다")
    func cancelledMeasuringKeepsLastTake() throws {
        var timeline = RecordingTimeline()
        try recordTake(sine(150, seconds: 5), keepSeconds: 5, into: &timeline)
        timeline.beginRecording(keepSeconds: 10)
        timeline.receive((0..<100).map { PitchReading(time: 30 + Double($0) * 0.02, frequency: 300) }, isMeasuring: true)
        timeline.cancelMeasuring()

        let summary = try #require(timeline.lastTakeSummary(target: nil))
        #expect(abs(summary.median - 150) < 1)
        #expect(timeline.display.readings.compactMap(\.frequency).allSatisfy { abs($0 - 150) < 5 })
        #expect(timeline.finishMeasuring().isEmpty)
    }

    // MARK: - 버그 ③ 저장에 실패해도 "기록에 남겼어요"가 뜬다

    private struct DiskFull: Error {}

    private func makeArchive() -> (PracticeArchive, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)")
        return (PracticeArchive(inMemory: true, recordingsDirectory: directory), directory)
    }

    private func count<T: PersistentModel>(_ type: T.Type, in archive: PracticeArchive) throws -> Int {
        try archive.context.fetchCount(FetchDescriptor<T>())
    }

    @Test("버그 ③: 녹음 저장이 실패하면 오류가 호출한 쪽까지 오고, 만든 m4a 파일과 반쪽 기록이 남지 않는다")
    func recordingSaveFailureCleansUp() async throws {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = sine(200, seconds: 1)
        let summary = try #require(PitchSummary(voiced: [200], voicedSeconds: 1, duration: 1, target: nil))
        archive.simulatedSaveError = DiskFull()

        await #expect(throws: DiskFull.self) {
            try await archive.saveRecording(samples: samples, sampleRate: sampleRate, summary: summary, title: "",
                                            memo: "", language: .korean, recordedAt: .now)
        }
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(leftovers.isEmpty, "남은 파일: \(leftovers)")
        #expect(try count(SavedRecording.self, in: archive) == 0)
    }

    @Test("버그 ③: 연습 기록·기준 이력·모음 이력 저장이 실패하면 오류를 던지고 기록을 남기지 않는다")
    func otherSaveFailuresThrow() throws {
        let (archive, _) = makeArchive()
        var log = PracticeSessionLog(startedAt: Date(timeIntervalSince1970: 1_800_000_000), language: .korean)
        log.beginTake()
        log.add((0..<500).map { PitchReading(time: Double($0) * 0.02, frequency: 190) })
        let session = try #require(log.finish(at: Date(timeIntervalSince1970: 1_800_000_090), target: nil))
        let entry = VowelMap.Entry(f1: 750, f2: 1300, f1Spread: 730...770, f2Spread: 1280...1330,
                                   isF1Uncertain: false, measuredAt: .now)
        archive.simulatedSaveError = DiskFull()

        #expect(throws: DiskFull.self) { try archive.saveSession(session) }
        #expect(throws: DiskFull.self) { try archive.saveBaseline(VoiceBaseline(median: 150, low: 130, high: 175)) }
        #expect(throws: DiskFull.self) { try archive.saveVowel(entry, for: .a) }
        #expect(try count(PracticeSession.self, in: archive) == 0)
        #expect(try count(BaselineRecord.self, in: archive) == 0)
        #expect(try count(VowelRecord.self, in: archive) == 0)

        archive.simulatedSaveError = nil
        try archive.saveSession(session)
        #expect(try count(PracticeSession.self, in: archive) == 1)
    }

    /// 2초짜리 합성음 파일을 만들어 [높이] 탭에 불러온 상태
    private func managerWithImportedTake(frequency: Double) async throws -> (AudioInputManager, URL, URL) {
        let (archive, directory) = makeArchive()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).m4a")
        try AudioFileAnalyzer.writeM4A(samples: sine(frequency, seconds: 2), sampleRate: sampleRate, to: url)
        let audio = AudioInputManager(archive: archive)
        #expect(await audio.importRecording(from: url, title: "합성음"))
        audio.stop()  // 불러오면 바로 재생하므로 멈춘다
        return (audio, directory, url)
    }

    @Test("버그 ③: 녹음 저장이 실패하면 ‘기록에 남겼어요’가 되지 않고 안내가 나온다")
    func managerShowsSaveFailure() async throws {
        let (audio, directory, url) = try await managerWithImportedTake(frequency: 180)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: url)
        }
        audio.archive.simulatedSaveError = DiskFull()
        await audio.saveLastTake(memo: "", language: .korean, target: nil)
        #expect(!audio.lastTakeIsSaved)
        #expect(audio.lastTakeSavedRecordID == nil)
        #expect(audio.errorMessage == "기록을 저장하지 못했어요. 저장 공간을 확인해 주세요.")
    }

    @Test("버그 ③ 덤: 남긴 녹음을 [기록] 탭에서 지우면 [높이] 탭에서 다시 ‘기록에 남기기’를 할 수 있다")
    func savedTakeCanBeSavedAgainAfterDeletion() async throws {
        let (audio, directory, url) = try await managerWithImportedTake(frequency: 180)
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: url)
        }
        await audio.saveLastTake(memo: "", language: .korean, target: nil)
        #expect(audio.lastTakeIsSaved)
        let saved = try #require(try audio.archive.context.fetch(FetchDescriptor<SavedRecording>()).first)
        #expect(audio.lastTakeSavedRecordID == saved.persistentModelID)
        #expect(abs(saved.medianHz - (audio.lastTakeSummary(target: nil)?.median ?? 0)) < 1e-9)

        try audio.archive.delete(saved)
        #expect(!audio.lastTakeIsSaved)
        await audio.saveLastTake(memo: "", language: .korean, target: nil)
        #expect(audio.lastTakeIsSaved)
        #expect(try count(SavedRecording.self, in: audio.archive) == 1)
    }
}
