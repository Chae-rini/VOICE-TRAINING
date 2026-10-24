import CoreGraphics
import Foundation

/// 모음 지도(F1–F2 평면)의 규칙.
/// 방향은 음성학의 모음도와 같다: 가로는 F2가 높을수록 왼쪽(혀 앞쪽), 세로는 F1이 낮을수록 위(입을 좁게).
/// 성별 평균 같은 기준 위치는 두지 않는다 (원칙 3). 비교 대상은 내가 잰 내 모음뿐이다 (4단계-3).
enum VowelSpace {
    /// [Hz] 지도에 보이는 F1 범위 (세로)
    static let f1Range = 200.0...1100.0
    /// [Hz] 지도에 보이는 F2 범위 (가로)
    static let f2Range = 600.0...3000.0
    /// [Hz] 눈금
    static let f1Ticks: [Double] = [300, 500, 700, 900]
    static let f2Ticks: [Double] = [1000, 1500, 2000, 2500]

    /// 지도 위 한 점 (흔들림을 줄인 값)
    struct Point: Equatable {
        /// [Hz]
        let f1: Double
        /// [Hz]
        let f2: Double
        /// 목소리가 높아 F1이 배음 쪽으로 끌렸을 수 있음
        let isF1Uncertain: Bool
    }

    /// F1이 불확실한지: 목소리가 높고(F0 ≥ 200 Hz) F1이 2.5×F0보다 낮으면 가까운 배음으로 끌렸을 수 있다.
    /// 합성 모음 검증(4단계-1)에서 F0 200 Hz 이상, F1이 낮은 모음에서 최대 20~36% 오차를 본 것을 바탕으로 정했다.
    static func isF1Uncertain(f1: Double, f0: Double) -> Bool {
        f0 >= 200 && f1 < 2.5 * f0
    }

    /// 최근 점들(포먼트가 잡힌 것)의 중앙값. 3개 미만이면 nil — 한두 조각만으로는 흔들려서 보여 주지 않는다.
    static func current(_ readings: some Collection<PitchReading>) -> Point? {
        let voiced = readings.compactMap { reading -> (f0: Double, formants: FormantAnalyzer.Estimate)? in
            guard let f0 = reading.frequency, let formants = reading.formants else { return nil }
            return (f0, formants)
        }
        guard voiced.count >= 3 else { return nil }
        let f1 = median(voiced.map(\.formants.f1.frequency))
        let f2 = median(voiced.map(\.formants.f2.frequency))
        let f0 = median(voiced.map(\.f0))
        return Point(f1: f1, f2: f2, isF1Uncertain: isF1Uncertain(f1: f1, f0: f0))
    }

    /// 지도 안의 상대 위치 (0~1, 왼쪽 위가 (0, 0)). 범위를 벗어나면 가장자리에 붙인다.
    static func position(f1: Double, f2: Double) -> CGPoint {
        let x = 1 - (f2 - f2Range.lowerBound) / (f2Range.upperBound - f2Range.lowerBound)
        let y = (f1 - f1Range.lowerBound) / (f1Range.upperBound - f1Range.lowerBound)
        return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
