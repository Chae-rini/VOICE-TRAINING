/// 한 번 연습하는 시간. 성대를 무리하게 쓰지 않도록 최대 3분으로 제한한다.
enum PracticeDuration {
    static let range: ClosedRange<Double> = 10...180  // [s]
    static let step: Double = 10                      // [s]
    static let defaultSeconds: Double = 60            // [s]

    /// 범위 안으로 자르고 10초 단위로 맞춘다.
    static func normalized(_ seconds: Double) -> Double {
        let snapped = (seconds / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, snapped))
    }

    /// 예: 10 → "10초", 60 → "1분", 90 → "1분 30초"
    static func label(for seconds: Double) -> String {
        let total = Int(normalized(seconds))
        let minutes = total / 60
        let remainder = total % 60
        if minutes == 0 {
            return "\(remainder)초"
        }
        return remainder == 0 ? "\(minutes)분" : "\(minutes)분 \(remainder)초"
    }
}
