import Foundation
import SwiftData
import Testing
@testable import VoicePractice

/// 문장 끝 숫자를 기록(연습 기록의 녹음마다·남긴 녹음)에 남기기 (2026-10-30).
/// 그 전에는 [높이]의 마지막 녹음 카드에만 있어서, 다음 녹음을 시작하면 사라졌다.
@MainActor
struct PhraseEndingRecordTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// 목표 범위가 있던 녹음: 구절 11개 중 7개가 3반음 넘게 내려감, 평균 2.5반음
    private let withTarget = PhraseEndingSummary(
        phraseCount: 11, meanEndDropSemitones: 2.5, fallingOrDroppingCount: 7, fallingOrDroppingFraction: 7.0 / 11,
        endBelowTargetCount: 3, possibleFryCount: 1, outOfTargetAtEndFraction: 0.7, endFrameShare: 0.2
    )
    /// 목표 범위가 없던 녹음: 구절 5개 중 1개, 평균 0.5반음
    private let noTarget = PhraseEndingSummary(
        phraseCount: 5, meanEndDropSemitones: 0.5, fallingOrDroppingCount: 1, fallingOrDroppingFraction: 0.2,
        endBelowTargetCount: nil, possibleFryCount: 0, outOfTargetAtEndFraction: nil, endFrameShare: 0.25
    )

    private func makeArchive() -> (PracticeArchive, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phrase-\(UUID().uuidString)")
        return (PracticeArchive(inMemory: true, recordingsDirectory: directory), directory)
    }

    /// 녹음 두 번(문장 끝 숫자 `phrases`)을 한 연습 기록으로. 두 녹음 모두 10초 동안 180 Hz
    private func session(phrases: [PhraseEndingSummary?]) throws -> PracticeSessionLog.Summary {
        var log = PracticeSessionLog(startedAt: start, language: .korean)
        for (index, phrase) in phrases.enumerated() {
            log.beginTake()
            let readings = (0..<500).map { PitchReading(time: Double(index) * 100 + Double($0) * 0.02, frequency: 180) }
            log.add(readings)
            log.finishTake(readings: readings, duration: 10, target: 170...190, phraseEndings: phrase,
                           at: start.addingTimeInterval(Double(index + 1) * 40))
        }
        return try #require(log.finish(at: start.addingTimeInterval(90), target: 170...190))
    }

    @Test("연습 기록에 남긴 뒤 다시 읽어도 녹음마다의 문장 끝 숫자가 그대로다")
    func sessionRoundTrip() throws {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        try archive.saveSession(try session(phrases: [withTarget, noTarget]))

        let saved = try #require(try archive.context.fetch(FetchDescriptor<PracticeSession>()).first)
        #expect(saved.summary.takes.map(\.phraseEndings) == [withTarget, noTarget])
    }

    @Test("그 전에 남긴 기록은 문장 끝 칸이 비어 있어 숫자도, 요청문의 문장 끝 단락도 없다")
    func olderRecords() throws {
        let old = PracticeTake(PracticeSessionLog.Take(
            round: 1, endedAt: start,
            pitch: PitchSummary(duration: 10, voicedSeconds: 8, median: 180, p10: 170, p90: 190,
                                target: nil, inTargetFraction: nil)
        ))
        #expect(old.phraseCount == nil)
        #expect(old.phraseEndings == nil)
        #expect(!old.take.requestLine(sessionTarget: nil).contains("문장 끝"))
        #expect(!(try session(phrases: [nil, nil]).feedbackRequest().contains("문장 끝")))
        // 구절 수만 있고 다른 칸이 비면(망가진 기록) 숫자를 지어내지 않는다
        #expect(PhraseEndingSummary.restored(phraseCount: 3, fallingOrDroppingCount: nil, meanEndDropSemitones: 1,
                                             endBelowTargetCount: nil, possibleFryCount: 0,
                                             outOfTargetAtEndFraction: nil, endFrameShare: nil) == nil)
    }

    @Test("녹음 여러 개 합치기: 개수는 더하고 평균 하강 폭은 구절 수로 가중 평균, 합칠 수 없는 비율은 비운다")
    func combined() throws {
        let both = try #require(PhraseEndingSummary.combined([withTarget, noTarget]))
        #expect(both.phraseCount == 16)
        #expect(both.fallingOrDroppingCount == 8)
        #expect(both.fallingOrDroppingFraction == 0.5)
        #expect(both.meanEndDropSemitones == (2.5 * 11 + 0.5 * 5) / 16)
        #expect(both.endBelowTargetCount == 3, "목표가 있던 녹음만 더한다")
        #expect(both.possibleFryCount == 1)
        #expect(both.outOfTargetAtEndFraction == nil)
        #expect(both.endFrameShare == nil)

        #expect(PhraseEndingSummary.combined([noTarget])?.endBelowTargetCount == nil)
        #expect(PhraseEndingSummary.combined([]) == nil)
    }

    @Test("연습 기록 요청문: 녹음마다 줄에 문장 끝을 붙이고, 녹음 전체를 합친 문장 끝 단락을 녹음마다 아래에 넣는다")
    func sessionRequest() throws {
        let text = try session(phrases: [withTarget, noTarget]).feedbackRequest()
        #expect(text.contains("목표 범위 안 100%, 문장 끝 11개 중 7개 3반음 넘게 내려감, 평균 2.5반음 내려감\n"))
        #expect(text.contains("목표 범위 안 100%, 문장 끝 5개 중 1개 3반음 넘게 내려감, 평균 0.5반음 내려감\n"))
        let block = [
            "문장 끝 (녹음 2개를 합쳐서, 무성음 0.25초 이상에서 구절을 나누고, 구절마다 마지막 0.3초를 구절 전체와 비교)",
            "- 구절 수: 16개",
            "- 평균 하강 폭: 1.9반음 (구절 중앙값 → 마지막 0.3초 중앙값, +면 내려감)",
            "- 3반음 넘게 내려간 구절: 8개 (50%)",
            "- 끝 바닥(마지막 0.3초의 아래 10%)이 목표 하한 아래인 구절: 3개",
            "- 끝에 아주 낮은 높이가 이어진 구절(긁히는 소리 가능성, 높이 검출 오류일 수도 있음): 1개",
            "한국어 평서문은 끝이 내려가는 게 자연스러우니, 평평하게가 아니라 하강 폭 3반음 이내, 끝 바닥이 목표 하한 아래로 내려가지 않는지로 봐 주세요.",
        ].joined(separator: "\n")
        #expect(text.contains("평균 0.5반음 내려감\n\n" + block + "\n\n녹음 파일은 보내지 않았어요."))
        #expect(!text.contains("목표 범위 밖 순간 중"), "녹음마다의 비율은 합칠 수 없어 넣지 않는다")

        // 문장 끝 숫자가 있는 녹음만 합치고, 몇 개를 합쳤는지 밝힌다
        let partial = try session(phrases: [nil, withTarget]).feedbackRequest()
        #expect(partial.contains("문장 끝 (녹음 1개를 합쳐서,"))
        #expect(partial.contains("- 구절 수: 11개"))
    }

    @Test("남긴 녹음에 문장 끝 숫자를 남기고, 다시 읽어도 그대로다 (없이 남기면 비어 있다)")
    func savedRecording() async throws {
        let (archive, directory) = makeArchive()
        defer { try? FileManager.default.removeItem(at: directory) }
        let samples = Signal.sine(180, sampleRate: 48_000, count: 48_000)
        let summary = PitchSummary(duration: 1, voicedSeconds: 1, median: 180, p10: 179, p90: 181,
                                   target: 170...190, inTargetFraction: 1)
        let kept = try await archive.saveRecording(samples: samples, sampleRate: 48_000, summary: summary, title: "",
                                                   memo: "", language: .korean, recordedAt: start, phraseEndings: withTarget)
        let plain = try await archive.saveRecording(samples: samples, sampleRate: 48_000, summary: summary, title: "",
                                                    memo: "", language: .korean, recordedAt: start)
        #expect(kept.phraseEndings == withTarget)
        #expect(plain.phraseEndings == nil)

        let fetched = try archive.context.fetch(FetchDescriptor<SavedRecording>())
        #expect(Set(fetched.map { $0.phraseEndings?.phraseCount }) == [11, nil])
    }

    @Test("기록 화면의 한 줄 글")
    func lines() throws {
        let rules = try #require(PhraseEndingRules.standard)
        #expect(withTarget.headline(rules: rules) == "문장 끝 11개 중 7개가 3반음 넘게 내려갔어요")
        #expect(withTarget.shortPhrase(rules: rules) == "문장 끝 11개 중 7개 3반음 넘게 내려감, 평균 2.5반음 내려감")
        // 3반음 넘게 내려간 곳이 없을 때와 평균이 0.0반음일 때는 "0개 … 내려감", "평균 거의 그대로"라고 쓰지 않는다
        let flat = PhraseEndingSummary(phraseCount: 1, meanEndDropSemitones: 0.02, fallingOrDroppingCount: 0,
                                       fallingOrDroppingFraction: 0, endBelowTargetCount: 0, possibleFryCount: 0,
                                       outOfTargetAtEndFraction: nil, endFrameShare: 0.03)
        #expect(flat.shortPhrase(rules: rules) == "문장 끝 1개 중 3반음 넘게 내려간 곳 없음, 평균 하강 거의 없음")
        let rising = PhraseEndingSummary(phraseCount: 5, meanEndDropSemitones: -0.8, fallingOrDroppingCount: 0,
                                         fallingOrDroppingFraction: 0, endBelowTargetCount: nil, possibleFryCount: 0,
                                         outOfTargetAtEndFraction: nil, endFrameShare: 0.2)
        #expect(rising.shortPhrase(rules: rules) == "문장 끝 5개 중 3반음 넘게 내려간 곳 없음, 평균 0.8반음 올라감")
        let none = PhraseEndingSummary(phraseCount: 0, meanEndDropSemitones: nil, fallingOrDroppingCount: 0,
                                       fallingOrDroppingFraction: nil, endBelowTargetCount: nil, possibleFryCount: 0,
                                       outOfTargetAtEndFraction: nil, endFrameShare: nil)
        #expect(none.headline(rules: rules) == "문장으로 나눌 만큼 목소리가 이어진 곳이 없어요")
        #expect(none.shortPhrase(rules: rules) == nil)
    }
}
