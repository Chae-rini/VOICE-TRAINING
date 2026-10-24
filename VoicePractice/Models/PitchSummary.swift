import Foundation

/// 녹음 한 번의 피치 요약.
/// 성별 판정이 아니라, 앱이 잰 숫자와 내가 정한 목표 범위를 비교한 결과만 담는다.
struct PitchSummary: Equatable {
    /// [s] 녹음 길이
    let duration: TimeInterval
    /// [s] 목소리(유성음)로 잡힌 시간
    let voicedSeconds: TimeInterval
    /// [Hz] 피치 중앙값
    let median: Double
    /// [Hz] 아래 10% 지점 — 낮은 쪽 끝 (튀는 값은 뺀 범위)
    let p10: Double
    /// [Hz] 위 10% 지점 — 높은 쪽 끝
    let p90: Double
    /// [Hz] 비교한 목표 범위. 아직 정하지 않았으면 nil.
    let target: ClosedRange<Double>?
    /// 0~1. 목소리가 잡힌 순간 중 목표 범위 안에 있던 비율. 목표 범위가 없으면 nil.
    let inTargetFraction: Double?

    /// 목소리가 한 번도 잡히지 않았으면 nil.
    init?(readings: [PitchReading], duration: TimeInterval, target: ClosedRange<Double>?) {
        let voiced = readings.compactMap(\.frequency).sorted()
        guard !voiced.isEmpty else { return nil }

        // 점 사이 간격(분석 간격)으로 목소리가 잡힌 시간을 어림한다.
        let interval = readings.count > 1
            ? (readings[readings.count - 1].time - readings[0].time) / Double(readings.count - 1)
            : 0

        self.duration = duration
        voicedSeconds = Double(voiced.count) * interval
        median = Self.percentile(voiced, 0.5)
        p10 = Self.percentile(voiced, 0.1)
        p90 = Self.percentile(voiced, 0.9)
        self.target = target
        inTargetFraction = target.map { target in
            Double(voiced.filter { target.contains($0) }.count) / Double(voiced.count)
        }
    }

    /// 정렬된 값에서 `fraction`(0~1) 위치의 값. 사이에 있으면 양쪽 값을 직선으로 나눠 갖는다.
    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard sorted.count > 1 else { return sorted.first ?? .nan }
        let position = fraction * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    /// 예: 45 → "45초", 83 → "1분 23초", 60 → "1분"
    static func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let remainder = total % 60
        if minutes == 0 {
            return "\(remainder)초"
        }
        return remainder == 0 ? "\(minutes)분" : "\(minutes)분 \(remainder)초"
    }

    /// 구독 중인 AI 앱(ChatGPT, Claude 등)에 붙여 넣을 피드백 요청문.
    /// 녹음 파일 없이 글만 보낼 때는 음색을 짐작하지 말고 수치만 해석해 달라고 쓴다.
    /// 높이기·낮추기 어느 방향도 전제하지 않고, 사용자가 정한 목표 범위를 기준으로 봐 달라고 쓴다.
    func feedbackRequest(title: String, includesAudio: Bool) -> String {
        let targetLine = target.map { target in
            let percent = Int(((inTargetFraction ?? 0) * 100).rounded())
            return "\(Int(target.lowerBound))~\(Int(target.upperBound)) Hz (목표 범위 안 비율 \(percent)%)"
        } ?? "아직 정하지 않음"
        let direction = target == nil
            ? "목소리를 높이거나 낮추는 방향은 가정하지 말아 주세요."
            : "목소리를 높이거나 낮추는 방향은 가정하지 말고, 위의 내 목표 범위를 기준으로 봐 주세요."
        let request = includesAudio
            ? """
            떨림, 허스키함, 공명(밝고 가벼운 쪽인지, 어둡고 무게감 있는 쪽인지), 자연스러운 억양, 문장 끝 안정성 관점에서 피드백 부탁해요.
            함께 보낸 녹음 파일을 들을 수 있다면 파일도 참고해 주세요.
            """
            : """
            녹음 파일은 보내지 않았어요. 위 수치를 목표 범위와 비교해 해석하고, 다음 연습에서 해 볼 만한 점을 알려 주세요.
            떨림·허스키함·공명 같은 음색은 수치만으로는 알 수 없으니 짐작하지 말아 주세요.
            """
        return """
        [보이스 트레이닝 녹음 피드백 요청]
        녹음: \(title) (\(Self.durationLabel(duration)))

        아래 수치는 연습 앱이 기기 안에서 직접 잰 값이에요. (YIN 피치 검출, 70~400 Hz)
        - 목소리가 잡힌 시간: \(String(format: "%.1f", voicedSeconds))초
        - 피치 중앙값: \(Int(median.rounded())) Hz
        - 피치 범위(아래 10%~위 10%): \(Int(p10.rounded()))~\(Int(p90.rounded())) Hz
        - 내 목표 범위: \(targetLine)

        \(request)
        \(direction)
        성대에 무리가 가지 않는 방향으로 알려 주세요.
        수치는 자동 측정이라 오차가 있을 수 있어요.
        """
    }
}
