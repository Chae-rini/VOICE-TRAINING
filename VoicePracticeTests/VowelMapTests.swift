import Foundation
import Testing
@testable import VoicePractice

@MainActor
struct VowelMapTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    /// 0.02초 간격의 기록. `hasFormants`가 false인 점은 포먼트 없이(목소리만) 남긴다.
    private func readings(count: Int, f0: Double, f1: (Int) -> Double, f2: (Int) -> Double,
                          hasFormants: (Int) -> Bool = { _ in true }) -> [PitchReading] {
        (0..<count).map { i in
            PitchReading(time: Double(i) * 0.02, frequency: f0, formants: hasFormants(i) ? FormantAnalyzer.Estimate(
                f1: Formant(frequency: f1(i), bandwidth: 80),
                f2: Formant(frequency: f2(i), bandwidth: 100)
            ) : nil)
        }
    }

    @Test("모음 하나: 중앙값과 길게 내는 동안 흔들린 범위(25%~75%)를 잰다")
    func measures() throws {
        // 2초(100점). F1은 500~540, F2는 1500~1580에서 고르게 흔들림
        let entry = try #require(VowelMap.measure(
            readings(count: 100, f0: 130, f1: { 500 + Double($0 % 5) * 10 }, f2: { 1500 + Double($0 % 5) * 20 }),
            at: date
        ))
        #expect(entry.f1 == 520)
        #expect(entry.f2 == 1540)
        #expect(entry.f1Spread == 510...530)
        #expect(entry.f2Spread == 1520...1560)
        #expect(!entry.isF1Uncertain)
        #expect(entry.measuredAt == date)
    }

    @Test("포먼트가 1초보다 짧게 잡히면 저장하지 않는다")
    func tooShort() {
        // 3초(150점) 중 포먼트가 잡힌 것은 0.8초(40점)
        let short = readings(count: 150, f0: 130, f1: { _ in 500 }, f2: { _ in 1500 }, hasFormants: { $0 < 40 })
        #expect(VowelMap.measure(short) == nil)
        #expect(VowelMap.measure([PitchReading]()) == nil)
    }

    @Test("목소리가 높고 F1이 낮으면 잰 값도 F1 불확실로 남긴다")
    func uncertainF1() throws {
        let entry = try #require(VowelMap.measure(readings(count: 100, f0: 230, f1: { _ in 420 }, f2: { _ in 2300 })))
        #expect(entry.isF1Uncertain)
    }

    @Test("저장했다 다시 읽으면 같고, 같은 모음을 다시 재면 바뀌며, 망가진 값은 빈 지도로 읽는다")
    func storage() throws {
        let first = try #require(VowelMap.measure(readings(count: 100, f0: 130, f1: { _ in 800 }, f2: { _ in 1300 }), at: date))
        let second = try #require(VowelMap.measure(readings(count: 100, f0: 130, f1: { _ in 760 }, f2: { _ in 1250 }), at: date))

        var map = VowelMap()
        map.set(first, for: .a)
        #expect(map.measuredCount == 1)
        #expect(VowelMap(data: map.data) == map)

        map.set(second, for: .a)
        #expect(map[.a] == second)
        #expect(map.measuredCount == 1)
        #expect(map[.i] == nil)

        #expect(VowelMap(data: Data("망가진 값".utf8)).measuredCount == 0)
        #expect(VowelMap(data: nil).measuredCount == 0)
    }

    @Test("녹음 파일로 모음 하나를 잰다 (합성 '이', F0 120 Hz)")
    func measuresFromFileReadings() throws {
        let sampleRate = 48_000.0
        let shape = try #require(SyntheticVowel.shapes.first { $0.name == "이" })  // F1 300, F2 2300
        let samples = SyntheticVowel.make(formants: shape.formants, f0: 120, sampleRate: sampleRate, seconds: 2)
        let entry = try #require(VowelMap.measure(AudioFileAnalyzer.pitchReadings(samples, sampleRate: sampleRate)))
        #expect(abs(entry.f1 - 300) / 300 < 0.08)
        #expect(abs(entry.f2 - 2300) / 2300 < 0.08)
        #expect(!entry.isF1Uncertain)
    }
}
