import Foundation

/// 높이(Hz)를 반음 눈금으로 다루는 규칙.
/// 사람은 높이를 Hz의 차이가 아니라 비율로 느낀다 (반음 하나 = 2^(1/12)배, 약 6%).
/// 그래서 그래프는 Hz를 일정한 간격이 아니라 반음 간격으로 놓는다. 그러면 어느 높이에서든 같은 반음 폭이 같은 길이로 그려져,
/// 목표 범위가 높은 곳에 있든 낮은 곳에 있든 넓이가 공정하게 보인다 (원칙 3).
/// 저장하는 값과 화면의 숫자는 계속 Hz다. 위치만 반음 간격이다.
enum PitchScale {
    /// [반음] a에서 b까지: 12·log₂(b/a). b가 높으면 +, 낮으면 −.
    static func semitones(from a: Double, to b: Double) -> Double {
        12 * log2(b / a)
    }

    /// [Hz] `frequency`에서 반음 `semitones`개만큼 옮긴 높이
    static func frequency(_ frequency: Double, offsetBy semitones: Double) -> Double {
        frequency * pow(2, semitones / 12)
    }

    /// `range` 안의 상대 위치 (아래 끝 0, 위 끝 1). 반음 간격이라 같은 반음 폭은 어디서든 같은 길이다.
    static func position(of frequency: Double, in range: ClosedRange<Double>) -> Double {
        log(frequency / range.lowerBound) / log(range.upperBound / range.lowerBound)
    }

    /// `position(of:in:)`의 반대: 상대 위치(0~1) → Hz
    static func frequency(atPosition position: Double, in range: ClosedRange<Double>) -> Double {
        range.lowerBound * pow(range.upperBound / range.lowerBound, position)
    }

    /// 눈금 후보. 반음 눈금에서 고르게 보이는 숫자를 성긴 것부터 고른다.
    private static let tickSets: [[Double]] = [
        [70, 100, 150, 200, 300, 400],
        [70, 80, 90, 100, 125, 150, 175, 200, 250, 300, 350, 400],
        Array(stride(from: 70.0, through: 400.0, by: 10)),
    ]

    /// `range` 안의 눈금 [Hz]. 가장 성긴 묶음부터 보고, 눈금이 3개 이상 들어가는 첫 묶음을 쓴다.
    static func ticks(in range: ClosedRange<Double>) -> [Double] {
        for set in tickSets {
            let inside = set.filter { range.contains($0) }
            if inside.count >= 3 {
                return inside
            }
        }
        return tickSets[tickSets.count - 1].filter { range.contains($0) }
    }
}
