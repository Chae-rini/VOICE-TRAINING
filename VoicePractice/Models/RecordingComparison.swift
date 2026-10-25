import Foundation

/// 두 녹음 비교(A·B)의 계산 규칙. 어느 쪽이 낫다는 판정 없이 차이만 숫자로 말한다 (원칙 3).
enum RecordingComparison {
    /// 높이 분포 한 칸
    struct Bin: Identifiable, Equatable {
        /// [Hz] 칸의 가운데
        let center: Double
        /// 0~1. 목소리가 잡힌 점 중 이 칸에 든 비율
        let fraction: Double

        var id: Double { center }
    }

    /// [Hz] 분포 칸 너비
    static let binWidth = 5.0
    /// [Hz] 중앙값 차이가 이보다 작으면 "거의 같아요"
    static let sameMedianThreshold = 1.0

    /// 처음 열 때의 짝: 가장 먼저 남긴 녹음(A)과 가장 최근 녹음(B). 두 개가 안 되면 nil.
    static func defaultPair<T>(_ items: [T], date: (T) -> Date) -> (a: T, b: T)? {
        guard items.count >= 2 else { return nil }
        let sorted = items.sorted { date($0) < date($1) }
        return (sorted[0], sorted[sorted.count - 1])
    }

    /// 높낮이 폭 [반음]: 아래 10%~위 10%를 반음으로 센 값, 12·log₂(high/low). 억양의 오르내림이 클수록 크다.
    static func rangeSemitones(low: Double, high: Double) -> Double {
        guard low > 0, high > 0 else { return 0 }
        return VoiceBaseline.semitones(from: low, to: high)
    }

    /// B의 중앙값이 A와 얼마나 다른지 한 문장으로. 높다·낮다는 사실만 말하고 좋고 나쁨은 말하지 않는다.
    static func medianDifferenceText(a: Double, b: Double) -> String {
        let difference = b - a
        guard abs(difference) >= sameMedianThreshold else {
            return "두 녹음의 중앙값이 거의 같아요 (1 Hz 미만 차이)."
        }
        let semitones = abs(VoiceBaseline.semitones(from: a, to: b))
        let direction = difference > 0 ? "높아요" : "낮아요"
        return "B의 중앙값이 A보다 \(Int(abs(difference).rounded())) Hz \(direction) (반음 약 \(String(format: "%.1f", semitones))개)."
    }

    /// 목소리 높이들을 `domain` 안에서 5 Hz 칸으로 나눠 칸마다 비율을 낸다.
    /// 범위 밖 점도 전체 수에는 넣는다 (잘린 쪽의 비율이 부풀지 않게).
    static func distribution(_ frequencies: [Double], in domain: ClosedRange<Double>,
                             binWidth: Double = binWidth) -> [Bin] {
        guard !frequencies.isEmpty else { return [] }
        let start = (domain.lowerBound / binWidth).rounded(.down) * binWidth
        let binCount = max(Int(((domain.upperBound - start) / binWidth).rounded(.up)), 1)
        var counts = Array(repeating: 0, count: binCount)
        for frequency in frequencies where domain.contains(frequency) {
            counts[min(Int((frequency - start) / binWidth), binCount - 1)] += 1
        }
        let total = Double(frequencies.count)
        return counts.enumerated().map { index, count in
            Bin(center: start + (Double(index) + 0.5) * binWidth, fraction: Double(count) / total)
        }
    }

    /// 분포 그래프 가로축 [Hz]: 두 녹음의 아래 2%~위 2%와 목표 범위가 들어가게 (드물게 튀는 값은 뺀다).
    static func domain(_ a: [Double], _ b: [Double], target: ClosedRange<Double>?) -> ClosedRange<Double> {
        var values: [Double] = []
        for voiced in [a, b] where !voiced.isEmpty {
            let sorted = voiced.sorted()
            values += [PitchSummary.percentile(sorted, 0.02), PitchSummary.percentile(sorted, 0.98)]
        }
        return PracticeHistory.pitchDomain(values: values, target: target, baseline: nil)
    }
}
