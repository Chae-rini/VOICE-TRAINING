import CoreGraphics
import Foundation
import Testing
@testable import VoicePractice

@MainActor
struct VowelSpaceTests {
    private func reading(_ time: Double, f0: Double?, f1: Double, f2: Double) -> PitchReading {
        PitchReading(time: time, frequency: f0, formants: FormantAnalyzer.Estimate(
            f1: Formant(frequency: f1, bandwidth: 80),
            f2: Formant(frequency: f2, bandwidth: 100)
        ))
    }

    @Test("F1 불확실 표시: 목소리가 200 Hz 이상이고 F1이 2.5×F0보다 낮을 때만", arguments: [
        (300.0, 150.0, false),  // 목소리가 낮으면 믿는다
        (380.0, 200.0, true),   // 2×F0 근처로 끌렸을 수 있음
        (800.0, 200.0, false),  // F1이 충분히 높음
        (600.0, 300.0, true),
        (800.0, 300.0, false),
    ])
    func f1Uncertainty(f1: Double, f0: Double, expected: Bool) {
        #expect(VowelSpace.isF1Uncertain(f1: f1, f0: f0) == expected)
    }

    @Test("지도 방향: F2가 높을수록 왼쪽(혀 앞쪽), F1이 높을수록 아래(입 크게), 범위 밖은 가장자리에")
    func orientation() {
        #expect(VowelSpace.position(f1: 200, f2: 3000) == CGPoint(x: 0, y: 0))
        #expect(VowelSpace.position(f1: 1100, f2: 600) == CGPoint(x: 1, y: 1))
        #expect(VowelSpace.position(f1: 500, f2: 2300).x < VowelSpace.position(f1: 500, f2: 900).x)
        #expect(VowelSpace.position(f1: 800, f2: 1300).y > VowelSpace.position(f1: 300, f2: 1300).y)
        #expect(VowelSpace.position(f1: 50, f2: 5000) == CGPoint(x: 0, y: 0))
    }

    @Test("지금 점은 최근 점들의 중앙값이고, 포먼트가 잡힌 점이 3개 미만이면 보여 주지 않는다")
    func currentPoint() throws {
        let readings = [
            reading(0.00, f0: 120, f1: 500, f2: 1500),
            reading(0.02, f0: 120, f1: 520, f2: 1550),
            reading(0.04, f0: 120, f1: 900, f2: 2500),  // 튀는 값은 중앙값에서 빠진다
            PitchReading(time: 0.06, frequency: nil),
            reading(0.08, f0: 120, f1: 510, f2: 1520),
        ]
        let point = try #require(VowelSpace.current(readings))
        #expect(point.f1 == 515)
        #expect(point.f2 == 1535)
        #expect(!point.isF1Uncertain)
        #expect(VowelSpace.current(Array(readings.prefix(2))) == nil)
    }

    @Test("목소리가 높고 F1이 낮으면 지금 점의 F1을 불확실로 표시한다")
    func currentPointUncertain() throws {
        let readings = (0..<4).map { reading(Double($0) * 0.02, f0: 220, f1: 420, f2: 2300) }
        #expect(try #require(VowelSpace.current(readings)).isF1Uncertain)
    }

    @Test("기록에서 시간 구간의 점만 꺼낸다 (양 끝 포함)")
    func readingsInRange() {
        var history = PitchHistory(retention: 100)
        history.append(contentsOf: (0..<10).map { PitchReading(time: Double($0), frequency: 200) })
        #expect(history.readings(in: 2...5).map(\.time) == [2, 3, 4, 5])
        #expect(history.readings(in: 2.5...2.9).isEmpty)
        #expect(history.readings(in: -5...0).map(\.time) == [0])
        #expect(history.readings(in: 9...20).map(\.time) == [9])
    }

    @Test("녹음 파일을 분석하면 피치와 함께 포먼트도 담긴다 (합성 '아', F0 120 Hz)")
    func fileReadingsCarryFormants() throws {
        let sampleRate = 48_000.0
        let shape = SyntheticVowel.shapes[0]  // 아: F1 800, F2 1300
        let samples = SyntheticVowel.make(formants: shape.formants, f0: 120, sampleRate: sampleRate, seconds: 1)
        let readings = AudioFileAnalyzer.pitchReadings(samples, sampleRate: sampleRate)
        #expect(readings.filter { $0.formants != nil }.count > readings.count / 2)

        let point = try #require(VowelSpace.current(readings.filter { $0.time > 0.2 }))
        #expect(abs(point.f1 - 800) / 800 < 0.08)
        #expect(abs(point.f2 - 1300) / 1300 < 0.08)
    }
}
