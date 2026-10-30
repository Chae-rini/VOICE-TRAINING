import Foundation
import Testing
@testable import VoicePractice

/// 구절별 문장 끝 분석 (2026-10-25).
/// 입력과 기대값은 웹 테스트(`web/test/phraseEnding.test.ts`)와 같은 파일 `PhraseEndingCases.json`을 쓴다.
/// 두 쪽이 같은 기대값을 통과하면 iOS와 웹이 같은 결과를 낸다는 뜻이다.
/// 파일은 `Tools/PhraseEndingCases/make_cases.py`가 만들고, 기대값은 경우마다 손으로 셈한 값이다 (셈은 그 스크립트의 주석).
@MainActor
struct PhraseEndingAnalysisTests {
    // MARK: - 테스트 입력 파일의 모양

    private struct Fixture: Decodable {
        let frameInterval: Double
        let endTypeCases: [EndTypeCase]
        let fryRunCases: [FryRunCase]
        let cases: [Case]
    }

    private struct EndTypeCase: Decodable {
        let drop: Double
        let type: String
    }

    private struct FryRunCase: Decodable {
        let frameInterval: Double
        let frames: Int
    }

    private struct Case: Decodable {
        let name: String
        let target: [Double]?
        /// [시각 s, Hz 또는 null]
        let readings: [[Double?]]
        let expected: Expected
    }

    private struct Expected: Decodable {
        let phrases: [ExpectedPhrase]
        let summary: ExpectedSummary
    }

    private struct ExpectedPhrase: Decodable {
        let startTime: Double
        let endTime: Double
        let voicedFrameCount: Int
        let endFrameCount: Int
        let phraseMedian: Double
        let endMedian: Double
        let endFloor: Double
        let endDropSemitones: Double
        let endBelowTarget: Bool?
        let endType: String
        let possibleFry: Bool
    }

    private struct ExpectedSummary: Decodable {
        let phraseCount: Int
        let meanEndDropSemitones: Double?
        let fallingOrDroppingCount: Int
        let fallingOrDroppingFraction: Double?
        let endBelowTargetCount: Int?
        let possibleFryCount: Int
        let outOfTargetAtEndFraction: Double?
        let endFrameShare: Double?
    }

    /// 이 테스트 파일 옆의 `PhraseEndingCases.json`. 시뮬레이터는 Mac의 파일을 그대로 읽을 수 있다.
    private func loadFixture() throws -> Fixture {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("PhraseEndingCases.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    private func rules() throws -> PhraseEndingRules {
        try #require(PhraseEndingRules.standard, "앱 안의 PhraseEndingRules.json을 읽지 못했다")
    }

    /// 두 값이 1e-9 안에서 같은지. 둘 다 nil이어도 같다.
    private func close(_ actual: Double?, _ expected: Double?, tolerance: Double = 1e-9) -> Bool {
        switch (actual, expected) {
        case (nil, nil): true
        case let (actual?, expected?): abs(actual - expected) <= tolerance
        default: false
        }
    }

    // MARK: - 기준값

    @Test("기준값: 앱 안의 파일은 저장소의 PhraseEndingRules.json과 같다")
    func rulesMatchSourceFile() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("VoicePractice/Models/PhraseEndingRules.json")
        let fromSource = try JSONDecoder().decode(PhraseEndingRules.self, from: Data(contentsOf: source))
        #expect(try rules() == fromSource)
        #expect(fromSource.endWindowSeconds == 0.3)
        #expect(fromSource.fryMinimumFrames == 5)
    }

    @Test("종류: 하강 폭 경계값은 아래 종류에 든다 (≤ −2 rise, ≤ 3 stable, ≤ 5 falling)")
    func endTypeBoundaries() throws {
        let rules = try rules()
        for item in try loadFixture().endTypeCases {
            #expect(PhraseEndType(dropSemitones: item.drop, rules: rules).rawValue == item.type, "하강 \(item.drop)반음")
        }
    }

    @Test("긁히는 소리 연속 기준: 10 ms × 5 = 50 ms를 점 간격으로 나눠 올림 (48 kHz → 3점)")
    func fryRunConversion() throws {
        let rules = try rules()
        for item in try loadFixture().fryRunCases {
            #expect(rules.fryMinimumRun(frameInterval: item.frameInterval) == item.frames, "간격 \(item.frameInterval) s")
        }
    }

    // MARK: - 합성 피치

    @Test("합성 피치 9가지: 평평, 4반음 하강, 질문형 상승, 끝 90 Hz 6점, 250 ms로 나뉜 두 구절과 그 경계, 짧은 구절, 목표 없음, 목소리 없음")
    func fixtureCases() throws {
        let rules = try rules()
        let fixture = try loadFixture()
        #expect(fixture.cases.count == 9)

        for item in fixture.cases {
            let readings = item.readings.map { PitchReading(time: $0[0] ?? .nan, frequency: $0[1]) }
            let target = item.target.map { $0[0]...$0[1] }
            let analysis = PhraseEndingAnalysis(readings: readings, target: target, rules: rules)
            let name = item.name

            #expect(close(analysis.frameInterval, fixture.frameInterval, tolerance: 1e-12), "\(name): 점 간격")
            #expect(analysis.phrases.count == item.expected.phrases.count, "\(name): 구절 수")
            for (index, (actual, expected)) in zip(analysis.phrases, item.expected.phrases).enumerated() {
                let label = "\(name) 구절 \(index + 1)"
                #expect(close(actual.startTime, expected.startTime), "\(label): 시작")
                #expect(close(actual.endTime, expected.endTime), "\(label): 끝")
                #expect(actual.voicedFrameCount == expected.voicedFrameCount, "\(label): 유성 점 수")
                #expect(actual.endFrameCount == expected.endFrameCount, "\(label): 끝 점 수")
                #expect(close(actual.phraseMedian, expected.phraseMedian), "\(label): 구절 중앙값")
                #expect(close(actual.endMedian, expected.endMedian), "\(label): 끝 중앙값")
                #expect(close(actual.endFloor, expected.endFloor), "\(label): 끝 바닥")
                #expect(close(actual.endDropSemitones, expected.endDropSemitones), "\(label): 하강 폭")
                #expect(actual.endBelowTarget == expected.endBelowTarget, "\(label): 목표 하한 아래")
                #expect(actual.endType.rawValue == expected.endType, "\(label): 종류")
                #expect(actual.possibleFry == expected.possibleFry, "\(label): 긁히는 소리 가능성")
            }

            let summary = analysis.summary
            let expected = item.expected.summary
            #expect(summary.phraseCount == expected.phraseCount, "\(name): 요약 구절 수")
            #expect(close(summary.meanEndDropSemitones, expected.meanEndDropSemitones), "\(name): 평균 하강")
            #expect(summary.fallingOrDroppingCount == expected.fallingOrDroppingCount, "\(name): falling+dropping 수")
            #expect(close(summary.fallingOrDroppingFraction, expected.fallingOrDroppingFraction), "\(name): falling+dropping 비율")
            #expect(summary.endBelowTargetCount == expected.endBelowTargetCount, "\(name): 목표 하한 아래 구절 수")
            #expect(summary.possibleFryCount == expected.possibleFryCount, "\(name): 긁히는 소리 가능성 구절 수")
            #expect(close(summary.outOfTargetAtEndFraction, expected.outOfTargetAtEndFraction), "\(name): 목표 밖 중 끝 비율")
            #expect(close(summary.endFrameShare, expected.endFrameShare), "\(name): 끝 점 비율")
        }
    }

    // MARK: - 글 (웹 테스트와 같은 문장을 기대한다)

    /// 입력 파일에서 이름으로 고른 경우의 점·목표 범위·분석
    private func analyzed(_ name: String) throws -> (readings: [PitchReading], target: ClosedRange<Double>?, analysis: PhraseEndingAnalysis) {
        let cases = try loadFixture().cases
        let item = try #require(cases.first(where: { $0.name == name }), "\(name) 경우가 없다")
        let readings = item.readings.map { PitchReading(time: $0[0] ?? .nan, frequency: $0[1]) }
        let target = item.target.map { $0[0]...$0[1] }
        return (readings, target, PhraseEndingAnalysis(readings: readings, target: target, rules: try rules()))
    }

    @Test("글: 4반음 하강 — 요약 한 줄, 숫자, 안내, 구절 한 줄")
    func textForFalling() throws {
        let analysis = try analyzed("4반음 하강").analysis
        #expect(analysis.headline == "문장 끝 1개 중 1개가 3반음 넘게 내려갔어요")
        #expect(analysis.detailLines == [
            "평균 4.0반음 내려감",
            "바닥이 목표 하한(180 Hz) 아래로 내려간 끝: 1개",
            "목표 범위 밖 순간의 100%가 문장 끝 0.3초에 있어요 (문장 끝은 목소리의 25%)",
        ])
        #expect(analysis.guidance == "끝이 내려가는 건 자연스러워요. 바닥이 목표 하한 아래로 내려가지 않게만 해 보세요.")
        let phrase = try #require(analysis.phrases.first)
        #expect(phrase.endType.label == "내려감")
        #expect(phrase.pitchLine == "200 → 159 Hz")
        #expect(phrase.dropLabel == "4.0반음 내려감")
        #expect(phrase.notes == ["바닥 159 Hz · 목표 하한 아래"])
    }

    @Test("글: 상승·평평·긁힘·목표 없음·목소리 없음")
    func textForOtherCases() throws {
        let rise = try analyzed("질문형 상승").analysis
        #expect(rise.headline == "문장 끝 1개 중 3반음 넘게 내려간 곳은 없어요")
        #expect(rise.phrases.first?.dropLabel == "3.0반음 올라감")
        #expect(rise.phrases.first?.endType.label == "올라감")

        #expect(try analyzed("평평한 구절").analysis.phrases.first?.dropLabel == "거의 그대로")

        let fry = try analyzed("끝에 90 Hz 6점 연속 (긁히는 소리 가능성), 끊긴 2점씩은 아님").analysis
        #expect(fry.detailLines == [
            "평균 하강 거의 없음",
            "바닥이 목표 하한(150 Hz) 아래로 내려간 끝: 2개",
            "목표 범위 밖 순간의 100%가 문장 끝 0.3초에 있어요 (문장 끝은 목소리의 26%)",
            "끝이 긁혔을 수도 있는 곳: 1개 (높이를 잘못 읽었을 수도 있어요)",
        ])
        #expect(fry.phrases.first?.notes == ["바닥 90 Hz · 목표 하한 아래", "긁혔을 수도 있어요"])

        let noTarget = try analyzed("목표 범위 없음").analysis
        #expect(noTarget.detailLines == ["평균 4.0반음 내려감"])
        #expect(noTarget.guidance == "끝이 내려가는 건 자연스러워요. 3반음 안쪽으로만 내려가게 해 보세요.")

        let silent = try analyzed("목소리 없음").analysis
        #expect(silent.headline == "문장으로 나눌 만큼 목소리가 이어진 곳이 없어요")
        #expect(silent.detailLines.isEmpty)
        #expect(silent.requestLines.isEmpty)
    }

    @Test("요청문: 수치 아래에 문장 끝 요약을 빈 줄로 감싸 넣고, 목표가 없으면 목표 줄을 뺀다")
    func feedbackRequest() throws {
        let (readings, target, analysis) = try analyzed("4반음 하강")
        let summary = try #require(PitchSummary(readings: readings, duration: 2, target: target))
        let lines = [
            "문장 끝 (무성음 0.25초 이상에서 구절을 나누고, 구절마다 마지막 0.3초를 구절 전체와 비교)",
            "- 구절 수: 1개",
            "- 평균 하강 폭: 4.0반음 (구절 중앙값 → 마지막 0.3초 중앙값, +면 내려감)",
            "- 3반음 넘게 내려간 구절: 1개 (100%)",
            "- 끝 바닥(마지막 0.3초의 아래 10%)이 목표 하한 아래인 구절: 1개",
            "- 목표 범위 밖 순간 중 문장 끝 0.3초에 있던 비율: 100% (문장 끝은 목소리가 잡힌 시간의 25%)",
            "- 끝에 아주 낮은 높이가 이어진 구절(긁히는 소리 가능성, 높이 검출 오류일 수도 있음): 0개",
            "한국어 평서문은 끝이 내려가는 게 자연스러우니, 평평하게가 아니라 하강 폭 3반음 이내, 끝 바닥이 목표 하한 아래로 내려가지 않는지로 봐 주세요.",
        ]
        #expect(analysis.requestLines == lines)

        let request = summary.feedbackRequest(title: "방금 녹음", includesAudio: false, phraseEndings: analysis)
        #expect(request.contains("목표 범위 안 비율 75%)\n\n" + lines.joined(separator: "\n") + "\n\n녹음 파일은 보내지 않았어요."))

        // 구절이 없거나 분석이 없으면 예전 요청문 그대로
        let plain = summary.feedbackRequest(title: "방금 녹음", includesAudio: false)
        #expect(plain.contains("목표 범위 안 비율 75%)\n\n녹음 파일은 보내지 않았어요."))
        #expect(!plain.contains("문장 끝 ("))
        let silent = try analyzed("목소리 없음").analysis
        #expect(summary.feedbackRequest(title: "방금 녹음", includesAudio: false, phraseEndings: silent) == plain)

        let noTarget = try analyzed("목표 범위 없음").analysis
        #expect(noTarget.requestLines == [lines[0], lines[1], lines[2], lines[3], lines[6],
                                          "한국어 평서문은 끝이 내려가는 게 자연스러우니, 평평하게가 아니라 하강 폭 3반음 이내인지로 봐 주세요."])
    }
}
