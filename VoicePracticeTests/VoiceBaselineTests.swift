import Foundation
import Testing
@testable import VoicePractice

@MainActor
struct VoiceBaselineTests {
    /// 0.02초 간격의 피치 기록. nil은 무음.
    private func readings(_ frequencies: [Double?]) -> [PitchReading] {
        frequencies.enumerated().map { PitchReading(time: Double($0.offset) * 0.02, frequency: $0.element) }
    }

    @Test("기준 목소리: 중앙값과 아래·위 10% 지점을 잰다")
    func measures() {
        // 3초(150점) 동안 100~249 Hz가 고르게 잡힘
        let result = VoiceBaseline.measure(readings((0..<150).map { Double(100 + $0) }))
        guard case .measured(let baseline) = result else {
            Issue.record("측정되지 않음: \(result)")
            return
        }
        #expect(abs(baseline.median - 174.5) < 1e-9)
        #expect(abs(baseline.low - 114.9) < 1e-9)
        #expect(abs(baseline.high - 234.1) < 1e-9)
    }

    @Test("목소리가 2초보다 짧게 잡히면 다시 재자고 한다")
    func tooLittleVoice() {
        let oneSecondOfVoice: [Double?] = (0..<500).map { $0 < 50 ? 200 : nil }  // 10초 중 1초
        #expect(VoiceBaseline.measure(readings(oneSecondOfVoice)) == .tooLittleVoice)
        #expect(VoiceBaseline.measure(readings(Array(repeating: nil, count: 500))) == .tooLittleVoice)
        #expect(VoiceBaseline.measure([]) == .tooLittleVoice)

        let enoughVoice: [Double?] = (0..<500).map { $0 < 110 ? 200 : nil }  // 2.2초
        #expect(VoiceBaseline.measure(readings(enoughVoice)) != .tooLittleVoice)
    }

    @Test("처음 목표 범위는 기준 중앙값 ±20 Hz, 5 Hz 단위, 그래프 범위 안", arguments: [
        (196.3, 175.0...215.0),
        (150.0, 130.0...170.0),
        (75.0, 70.0...110.0),    // 아래 끝: 70 Hz 아래로 내려가지 않게 민다
        (395.0, 360.0...400.0),  // 위 끝
    ])
    func initialTarget(median: Double, expected: ClosedRange<Double>) {
        #expect(VoiceBaseline(median: median, low: median - 10, high: median + 10).initialTarget == expected)
    }

    @Test("기준에서 '많이 떨어짐'은 반음 6개 기준이고, 위·아래 어느 쪽이든 똑같이 판단한다")
    func farFromBaseline() {
        #expect(abs(VoiceBaseline.semitones(from: 220, to: 440) - 12) < 1e-9)
        #expect(abs(VoiceBaseline.semitones(from: 220, to: 110) + 12) < 1e-9)
        #expect(VoiceBaseline.isFar(280...320, from: 200))   // 가운데 300 Hz: 위로 약 7반음
        #expect(VoiceBaseline.isFar(120...140, from: 200))   // 가운데 130 Hz: 아래로 약 7.5반음
        #expect(!VoiceBaseline.isFar(230...270, from: 200))  // 가운데 250 Hz: 위로 약 3.9반음
        #expect(!VoiceBaseline.isFar(180...220, from: 200))
    }

    @Test("녹음 파일로도 기준을 잰다 (220 Hz 소리 10초)")
    func measuresFromFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("baseline-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try AudioFileAnalyzer.writeWAV(samples: Signal.sine(220, sampleRate: 48_000, count: 48_000 * 10),
                                       sampleRate: 48_000, to: url)

        let result = VoiceBaseline.measure(try AudioFileAnalyzer.analyze(url: url).readings)
        guard case .measured(let baseline) = result else {
            Issue.record("측정되지 않음: \(result)")
            return
        }
        #expect(abs(baseline.median - 220) < 1)
    }
}

@MainActor
struct TargetRangeStoreTests {
    /// 테스트마다 비어 있는 저장소를 따로 쓴다 (앱의 실제 설정은 건드리지 않음).
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "VoicePracticeTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            Issue.record("저장소를 만들지 못함")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test("새로 설치한 사람: 목표 범위 없이 시작하고, 기준을 재면 기준 ±20 Hz로 정한다")
    func freshInstall() {
        withDefaults { defaults in
            TargetRangeStore.preserveExistingTarget(in: defaults)
            #expect(TargetRangeStore.savedTarget(in: defaults) == nil)
            #expect(TargetRangeStore.shouldApplyInitialTarget(in: defaults))

            let baseline = VoiceBaseline(median: 150, low: 130, high: 175)
            TargetRangeStore.save(baseline, applyingTarget: true, in: defaults)
            #expect(TargetRangeStore.savedTarget(in: defaults) == 130...170)
            #expect(TargetRangeStore.savedBaseline(in: defaults) == baseline)
        }
    }

    @Test("저장해 둔 목표 범위는 기준을 재도 그대로다")
    func keepsSavedTarget() {
        withDefaults { defaults in
            defaults.set(150.0, forKey: TargetRangeStore.lowerKey)
            defaults.set(170.0, forKey: TargetRangeStore.upperKey)
            TargetRangeStore.preserveExistingTarget(in: defaults)
            #expect(TargetRangeStore.savedTarget(in: defaults) == 150...170)
            #expect(!TargetRangeStore.shouldApplyInitialTarget(in: defaults))

            TargetRangeStore.save(VoiceBaseline(median: 250, low: 220, high: 280), applyingTarget: false, in: defaults)
            #expect(TargetRangeStore.savedTarget(in: defaults) == 150...170)
            #expect(TargetRangeStore.savedBaseline(in: defaults)?.median == 250)
        }
    }

    @Test("예전 버전을 쓰던 사람이 목표 범위를 따로 저장한 적 없으면, 보던 180~220 Hz를 그대로 남긴다")
    func preservesLegacyDefault() {
        withDefaults { defaults in
            defaults.set(60.0, forKey: "practiceDurationSeconds")  // 예전 버전에서 연습 시간을 바꾼 적 있음
            TargetRangeStore.preserveExistingTarget(in: defaults)
            #expect(TargetRangeStore.savedTarget(in: defaults) == 180...220)
            #expect(!TargetRangeStore.shouldApplyInitialTarget(in: defaults))
        }
    }

    @Test("한쪽 값만 저장돼 있으면 나머지는 예전 기본값으로 채워 목표 범위를 지킨다")
    func fillsMissingBound() {
        withDefaults { defaults in
            defaults.set(160.0, forKey: TargetRangeStore.lowerKey)
            TargetRangeStore.preserveExistingTarget(in: defaults)
            #expect(TargetRangeStore.savedTarget(in: defaults) == 160...220)
        }
    }

    @Test("예전 사용자 확인은 처음 한 번만: 새로 설치한 뒤 다른 설정을 바꿔도 목표 범위를 지어내지 않는다")
    func migrationRunsOnce() {
        withDefaults { defaults in
            TargetRangeStore.preserveExistingTarget(in: defaults)
            defaults.set(90.0, forKey: "practiceDurationSeconds")
            TargetRangeStore.preserveExistingTarget(in: defaults)
            #expect(TargetRangeStore.savedTarget(in: defaults) == nil)
        }
    }
}
