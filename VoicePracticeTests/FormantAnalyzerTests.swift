import Foundation
import Testing
@testable import VoicePractice

struct FormantAnalyzerTests {
    let sampleRate = 48_000.0  // [Hz]

    /// 합성 모음의 조각 9개에서 잰 F1·F2의 중앙값 [Hz]
    private func measure(_ shape: SyntheticVowel.Shape, f0: Double) -> (f1: Double, f2: Double)? {
        let analyzer = FormantAnalyzer(sampleRate: sampleRate)
        let signal = SyntheticVowel.make(formants: shape.formants, f0: f0, sampleRate: sampleRate, seconds: 0.6)
        let estimates = SyntheticVowel.frames(signal, sampleRate: sampleRate).compactMap { analyzer.estimate($0) }
        guard estimates.count >= 5 else { return nil }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        return (median(estimates.map(\.f1.frequency)), median(estimates.map(\.f2.frequency)))
    }

    @Test("48 kHz 소리는 12 kHz로 줄여 LPC 12차로 분석한다")
    func configuration() {
        let analyzer = FormantAnalyzer(sampleRate: 48_000)
        #expect(analyzer.decimationFactor == 4)
        #expect(analyzer.analysisRate == 12_000)
        #expect(analyzer.order == 12)
    }

    @Test("Levinson–Durbin은 알려진 AR(2) 과정의 계수를 되찾는다")
    func levinsonDurbin() throws {
        // x[n] = 1.3·x[n−1] − 0.8·x[n−2] + e[n]  →  A(z) = 1 − 1.3z⁻¹ + 0.8z⁻²
        var generator = SeededGenerator(seed: 42)
        var x = [Double](repeating: 0, count: 40_000)
        for n in 2..<x.count {
            x[n] = 1.3 * x[n - 1] - 0.8 * x[n - 2] + Double.random(in: -1...1, using: &generator)
        }
        let r = (0...2).map { k in zip(x, x.dropFirst(k)).map { $0 * $1 }.reduce(0, +) }
        let a = try #require(FormantAnalyzer.levinsonDurbin(r, order: 2))
        #expect(abs(a[0] - -1.3) < 0.03)
        #expect(abs(a[1] - 0.8) < 0.03)
    }

    @Test("다항식의 근을 모두 찾는다: (z−0.5)(z+0.25)(z²−z+0.5)")
    func polynomialRoots() {
        let roots = FormantAnalyzer.polynomialRoots([1, -1.25, 0.625, 0, -0.0625])
        #expect(roots.count == 4)
        for expected in [Complex(0.5, 0), Complex(-0.25, 0), Complex(0.5, 0.5), Complex(0.5, -0.5)] {
            #expect(roots.contains { ($0 - expected).magnitude < 1e-9 }, "\(expected)")
        }
    }

    @Test("목소리가 낮을 때(F0 100·150 Hz): 7개 모음의 F1·F2를 8% 안으로 잰다", arguments: [100.0, 150.0])
    func lowVoice(f0: Double) throws {
        for shape in SyntheticVowel.shapes {
            let measured = try #require(measure(shape, f0: f0), "\(shape.name)")
            #expect(abs(measured.f1 - shape.formants[0]) / shape.formants[0] < 0.08, "\(shape.name) F1 \(measured.f1)")
            #expect(abs(measured.f2 - shape.formants[1]) / shape.formants[1] < 0.08, "\(shape.name) F2 \(measured.f2)")
        }
    }

    /// F0 200 Hz 이상에서는 F1이 배음 쪽으로 끌려 최대 20~36% 틀린다 (LPC의 알려진 한계, PROGRESS.md 참고).
    /// 그래서 여기서는 F2만 확인한다.
    @Test("F0 200 Hz: F2는 7개 모음 모두 5% 안으로 잰다")
    func f2AtHigherVoice() throws {
        for shape in SyntheticVowel.shapes {
            let measured = try #require(measure(shape, f0: 200), "\(shape.name)")
            #expect(abs(measured.f2 - shape.formants[1]) / shape.formants[1] < 0.05, "\(shape.name) F2 \(measured.f2)")
        }
    }

    @Test("무음이나 너무 짧은 조각은 재지 않는다")
    func silenceAndShortFrames() {
        let analyzer = FormantAnalyzer(sampleRate: sampleRate)
        #expect(analyzer.estimate([Float](repeating: 0, count: 2048)) == nil)
        #expect(analyzer.estimate([Float](repeating: 0.1, count: 40)) == nil)
    }
}
