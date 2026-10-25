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
}
