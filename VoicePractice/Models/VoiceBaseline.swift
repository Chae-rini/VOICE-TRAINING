import Foundation

/// 내 기준 목소리: 연습 문장을 편하게 읽었을 때 잰 피치.
/// 높다·낮다 같은 평가 없이, 목표 범위를 정하는 출발점으로만 쓴다.
/// 값은 기기 안(UserDefaults)에만 저장하고 공유 요청문에도 넣지 않는다.
struct VoiceBaseline: Equatable {
    /// [Hz] 피치 중앙값
    let median: Double
    /// [Hz] 아래 10% 지점
    let low: Double
    /// [Hz] 위 10% 지점
    let high: Double

    /// [s] 마이크로 잴 때의 녹음 길이
    static let recordingSeconds: TimeInterval = 10
    /// [s] 목소리가 이보다 짧게 잡히면 다시 재자고 안내한다.
    static let minimumVoicedSeconds: TimeInterval = 2
    /// [Hz] 처음 목표 범위는 기준 중앙값 ± 이 값
    static let initialTargetHalfWidth = 20.0
    /// [반음] 목표 범위 가운데가 기준에서 이만큼 이상 떨어지면 부드럽게 안내한다. 위·아래 어느 쪽이든 같다.
    static let farDistanceSemitones = 6.0
    /// 잴 때 읽을 연습 문장 (PracticeSentences 중 하나)
    static let readingSentence = "회의는 오후 두 시에 시작합니다."

    enum Measurement: Equatable {
        case measured(VoiceBaseline)
        /// 목소리가 거의 잡히지 않음 → 다시 재기
        case tooLittleVoice
    }

    /// 피치 기록으로 기준 목소리를 잰다. 목소리가 잡힌 시간이 2초보다 짧으면 `.tooLittleVoice`.
    static func measure(_ readings: [PitchReading]) -> Measurement {
        let voiced = readings.compactMap(\.frequency).sorted()
        // 점 사이 간격(분석 간격)으로 목소리가 잡힌 시간을 어림한다 (PitchSummary와 같은 방식).
        let interval = readings.count > 1
            ? (readings[readings.count - 1].time - readings[0].time) / Double(readings.count - 1)
            : 0
        guard Double(voiced.count) * interval >= minimumVoicedSeconds else { return .tooLittleVoice }
        return .measured(VoiceBaseline(
            median: PitchSummary.percentile(voiced, 0.5),
            low: PitchSummary.percentile(voiced, 0.1),
            high: PitchSummary.percentile(voiced, 0.9)
        ))
    }

    /// 처음 목표 범위: 중앙값 ±20 Hz. 가운데를 슬라이더와 같은 5 Hz 단위로 맞추고, 그래프 범위(70~400 Hz) 안으로 민다.
    var initialTarget: ClosedRange<Double> {
        let axis = PitchDetector.frequencyRange
        let half = Self.initialTargetHalfWidth
        let center = min(max((median / 5).rounded() * 5, axis.lowerBound + half), axis.upperBound - half)
        return (center - half)...(center + half)
    }

    /// 두 높이 사이의 거리 [반음]: 12·log₂(b/a). 위로 가면 +, 아래로 가면 −.
    static func semitones(from a: Double, to b: Double) -> Double {
        12 * log2(b / a)
    }

    /// 목표 범위 가운데가 기준 중앙값 `median`에서 반음 6개 이상 떨어졌는지 (방향 무관).
    static func isFar(_ target: ClosedRange<Double>, from median: Double) -> Bool {
        let center = (target.lowerBound + target.upperBound) / 2
        return abs(semitones(from: median, to: center)) >= farDistanceSemitones
    }
}

/// 목표 범위와 기준 목소리를 저장하는 키(UserDefaults)와 규칙. 화면은 같은 키로 @AppStorage를 쓴다.
enum TargetRangeStore {
    static let lowerKey = "targetLowerHz"
    static let upperKey = "targetUpperHz"
    static let baselineMedianKey = "baselineMedianHz"
    static let baselineLowKey = "baselineLowHz"
    static let baselineHighKey = "baselineHighHz"
    /// 처음 실행 때 "내 목소리 재기"를 한 번 띄웠는지
    static let baselinePromptShownKey = "baselinePromptShown"
    /// 예전 사용자 확인을 이미 했는지 (한 번만 한다)
    static let migrationDoneKey = "targetRangeMigrationDone"

    /// 예전 버전의 기본 목표 범위. 예전부터 쓰던 사람에게만 남겨 둔다.
    static let legacyDefault = 180.0...220.0
    /// 예전 버전에서 저장되던 설정. 하나라도 있으면 예전부터 쓰던 사람이다.
    static let legacyKeys = ["practiceDurationSeconds", "practiceRounds", "sentenceSource", "scriptCategory", "scriptLength"]

    /// 저장된 목표 범위. 없으면 nil.
    static func savedTarget(in defaults: UserDefaults) -> ClosedRange<Double>? {
        guard let lower = defaults.object(forKey: lowerKey) as? Double,
              let upper = defaults.object(forKey: upperKey) as? Double else { return nil }
        return min(lower, upper)...max(lower, upper)
    }

    /// 저장된 기준 목소리. 없으면 nil.
    static func savedBaseline(in defaults: UserDefaults) -> VoiceBaseline? {
        guard let median = defaults.object(forKey: baselineMedianKey) as? Double,
              let low = defaults.object(forKey: baselineLowKey) as? Double,
              let high = defaults.object(forKey: baselineHighKey) as? Double else { return nil }
        return VoiceBaseline(median: median, low: low, high: high)
    }

    /// 기준을 잰 뒤 "목표 범위를 기준에 맞추기"의 처음 상태: 저장된 목표 범위가 없을 때만 켠다.
    static func shouldApplyInitialTarget(in defaults: UserDefaults) -> Bool {
        savedTarget(in: defaults) == nil
    }

    /// 기준 목소리를 저장한다. `applyingTarget`이 true일 때만 목표 범위를 기준 ±20 Hz로 바꾼다.
    static func save(_ baseline: VoiceBaseline, applyingTarget: Bool, in defaults: UserDefaults) {
        defaults.set(baseline.median, forKey: baselineMedianKey)
        defaults.set(baseline.low, forKey: baselineLowKey)
        defaults.set(baseline.high, forKey: baselineHighKey)
        if applyingTarget {
            defaults.set(baseline.initialTarget.lowerBound, forKey: lowerKey)
            defaults.set(baseline.initialTarget.upperBound, forKey: upperKey)
        }
    }

    /// 앱을 켤 때 부른다 (실제로 확인하는 것은 처음 한 번뿐).
    /// 예전부터 쓰던 사람은 목표 범위를 따로 저장하지 않았어도 180~220 Hz를 보고 있었으므로 그 값을 그대로 저장해 둔다.
    /// 새로 설치한 사람은 아무것도 저장하지 않는다 — 목표 범위는 기준 목소리를 잰 뒤에 생긴다.
    static func preserveExistingTarget(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: migrationDoneKey) else { return }
        defaults.set(true, forKey: migrationDoneKey)

        let hasLower = defaults.object(forKey: lowerKey) != nil
        let hasUpper = defaults.object(forKey: upperKey) != nil
        let usedBefore = hasLower || hasUpper || legacyKeys.contains { defaults.object(forKey: $0) != nil }
        guard usedBefore else { return }
        if !hasLower {
            defaults.set(legacyDefault.lowerBound, forKey: lowerKey)
        }
        if !hasUpper {
            defaults.set(legacyDefault.upperBound, forKey: upperKey)
        }
    }
}
