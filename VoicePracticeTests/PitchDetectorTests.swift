import Foundation
import Testing
@testable import VoicePractice

/// 합성한 소리를 넣어서 피치 검출기가 맞는 Hz를 돌려주는지 확인한다.
struct PitchDetectorTests {
    @Test("순음(사인파)의 주파수를 0.5Hz 이내로 찾는다",
          arguments: [44_100.0, 48_000.0], [75.0, 120.0, 200.0, 350.0, 399.0])
    func pureTone(sampleRate: Double, frequency: Double) throws {
        let detector = PitchDetector(sampleRate: sampleRate)
        let frame = Signal.sine(frequency, sampleRate: sampleRate, count: detector.frameLength)
        let estimate = try #require(detector.detect(frame))
        #expect(abs(estimate.frequency - frequency) < 0.5)
    }

    @Test("배음이 섞인 목소리 같은 소리에서 기본주파수를 찾는다 (옥타브 오류 없음)")
    func harmonicTone() throws {
        let sampleRate = 48_000.0  // [Hz]
        let f0 = 180.0             // [Hz]
        let detector = PitchDetector(sampleRate: sampleRate)
        // k번째 배음의 진폭 ∝ 1/k (톱니파에 가까운 소리)
        let frame: [Float] = (0..<detector.frameLength).map { j in
            let t = Double(j) / sampleRate
            return Float((1...8).reduce(0.0) { sum, k in sum + 0.3 / Double(k) * sin(2 * .pi * f0 * Double(k) * t) })
        }
        let estimate = try #require(detector.detect(frame))
        #expect(abs(estimate.frequency - f0) < 0.5)
    }

    @Test("잡음이 조금 섞여도 기본주파수를 찾는다")
    func toneWithNoise() throws {
        let sampleRate = 48_000.0
        let detector = PitchDetector(sampleRate: sampleRate)
        let tone = Signal.sine(200, sampleRate: sampleRate, count: detector.frameLength)
        let noise = Signal.noise(count: detector.frameLength, amplitude: 0.05, seed: 42)
        let estimate = try #require(detector.detect(zip(tone, noise).map { $0 + $1 }))
        #expect(abs(estimate.frequency - 200) < 1)
    }

    @Test("무음은 nil")
    func silence() {
        let detector = PitchDetector(sampleRate: 48_000)
        #expect(detector.detect([Float](repeating: 0, count: detector.frameLength)) == nil)
    }

    @Test("아주 작은 소리(RMS가 기준 미만)는 nil")
    func tooQuiet() {
        let detector = PitchDetector(sampleRate: 48_000)
        let frame = Signal.sine(200, sampleRate: 48_000, count: detector.frameLength, amplitude: 0.001)
        #expect(detector.detect(frame) == nil)
    }

    @Test("잡음만 있으면 nil")
    func noiseOnly() {
        let detector = PitchDetector(sampleRate: 48_000)
        let frame = Signal.noise(count: detector.frameLength, amplitude: 0.3, seed: 7)
        #expect(detector.detect(frame) == nil)
    }

    @Test("70~400Hz 밖의 소리는 반이나 두 배 주파수로 잘못 읽지 않고 nil", arguments: [50.0, 500.0, 800.0])
    func outOfRange(frequency: Double) {
        let detector = PitchDetector(sampleRate: 48_000)
        let frame = Signal.sine(frequency, sampleRate: 48_000, count: detector.frameLength)
        #expect(detector.detect(frame) == nil)
    }
}

@MainActor
struct KoreanVowelTests {
    @Test("ㅐ와 ㅔ는 모두 '에'로 센다")
    func aeAndEAreMerged() {
        let counts = KoreanVowel.counts(in: "개미 세 마리")
        #expect(counts[.e] == 2)
        #expect(counts[.i] == 2)
        #expect(counts[.a] == 1)
    }

    @Test("이중모음과 한글이 아닌 글자는 세지 않는다")
    func ignoresDiphthongsAndNonHangul() {
        #expect(KoreanVowel.counts(in: "야 와 의 ABC 123").isEmpty)
    }

    @Test("많이 나온 모음부터, 개수가 같으면 아·어·오·우·으·이·에 순서")
    func mostFrequentOrdering() {
        let top = KoreanVowel.mostFrequent(in: "오 이 아 이 아")
        #expect(top.map { "\($0.vowel.rawValue)\($0.count)" } == ["아2", "이2"])
    }
}

/// 테스트용 합성 신호.
enum Signal {
    static func sine(_ frequency: Double, sampleRate: Double, count: Int, amplitude: Double = 0.5) -> [Float] {
        (0..<count).map { Float(amplitude * sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    /// −amplitude ~ +amplitude 균등 분포 잡음. 같은 seed면 항상 같은 잡음이 나온다.
    static func noise(count: Int, amplitude: Float, seed: UInt64) -> [Float] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { _ in Float.random(in: -amplitude...amplitude, using: &generator) }
    }
}

/// 재현 가능한 잡음을 위한 시드 고정 난수 생성기 (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
