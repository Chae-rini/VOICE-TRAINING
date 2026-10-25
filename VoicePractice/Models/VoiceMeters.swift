import Foundation

/// [높이] 탭의 음량 막대 계산.
/// 소리 크기는 이 기기 마이크가 받은 크기(dBFS, 0이 마이크가 받을 수 있는 최대)라 기기마다 다르다.
/// 귀에 들리는 절대 크기(dB SPL)가 아니므로 크다·작다를 평가하지 않고, 아주 큰 소리가 이어질 때만 목 상태를 묻는다 (원칙 4).
nonisolated enum LevelMeter {
    /// [dBFS] 막대 범위
    static let range = -60.0...0.0
    /// [dBFS] 무음(RMS 0)을 나타내는 값
    static let floor = -100.0
    /// [s] 평활 길이: 최근 이만큼의 소리 세기를 평균한다 (조각 하나마다 크게 흔들리지 않게)
    static let smoothingSeconds: TimeInterval = 0.3
    /// [dBFS] 큰 소리 기준 (임시값). 마이크 최대(0 dBFS)에서 10 dB 아래로, 보통 말하는 크기로는 닿지 않는다고 보고 정했다.
    /// 아이폰 `.measurement` 모드에서 실제로 말할 때의 값을 확인한 뒤 고친다.
    static let loudThreshold = -10.0
    /// [s] 큰 소리가 이만큼 이어지면 안내한다 (임시값). 한두 마디 크게 말한 것은 넘어간다.
    static let loudSeconds: TimeInterval = 3
    /// 그 시간 동안 이 비율 이상의 조각이 기준을 넘으면 '이어졌다'고 본다 (숨 쉬는 짧은 틈은 봐준다)
    static let loudFraction = 0.8

    /// 소리 조각 하나의 크기 [dBFS]: 20·log₁₀(RMS). 무음이면 `floor`.
    static func dBFS(rms: Double) -> Double {
        rms > 0 ? max(20 * log10(rms), floor) : floor
    }

    /// `time` 직전 0.3초의 평균 크기 [dBFS]. 크기를 dB로 평균하지 않고 세기(RMS²)로 평균한 뒤 dB로 바꾼다. 점이 없으면 nil.
    static func smoothedLevel(_ readings: some Collection<PitchReading>, at time: TimeInterval) -> Double? {
        let levels = readings.filter { $0.time > time - smoothingSeconds && $0.time <= time }.compactMap(\.level)
        guard !levels.isEmpty else { return nil }
        let power = levels.map { pow(10, $0 / 10) }.reduce(0, +) / Double(levels.count)
        return dBFS(rms: sqrt(power))
    }

    /// 큰 소리가 `loudSeconds`초 넘게 이어졌는지: 그 시간을 거의 다 채운 점들 중 80% 이상이 기준을 넘으면.
    static func isSustainedLoud(_ readings: some Collection<PitchReading>, at time: TimeInterval) -> Bool {
        let recent = readings.filter { $0.time > time - loudSeconds && $0.time <= time && $0.level != nil }
        guard let first = recent.first, time - first.time >= loudSeconds * 0.9 else { return false }
        let loud = recent.filter { ($0.level ?? floor) >= loudThreshold }.count
        return Double(loud) / Double(recent.count) >= loudFraction
    }

    /// 막대에서의 위치 (0 왼쪽 끝 −60 dBFS ~ 1 오른쪽 끝 0 dBFS)
    static func position(_ level: Double) -> Double {
        min(max((level - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
    }
}

/// [높이] 탭의 공명 밝기 막대 계산: 최근 목소리의 둘째 포먼트(F2)가 내 기준보다 밝은 쪽인지 어두운 쪽인지.
/// F2가 높을수록 소리가 밝게(앞쪽에서 울리게) 들린다. 성별 평균 같은 바깥 기준은 쓰지 않고 내 기준과만 비교한다 (원칙 3).
/// 문장 속 F2는 어떤 모음을 말했는지에 따라 크게 달라지므로, 같은 대본을 읽을 때 비교해야 뜻이 있다.
enum ResonanceMeter {
    /// [s] 최근 이만큼의 목소리 구간에서 F2 중앙값을 낸다
    static let windowSeconds: TimeInterval = 2.5
    /// 포먼트가 잡힌 점이 이보다 적으면(약 0.4초 분량) 흔들려서 보여 주지 않는다
    static let minimumPoints = 20
    /// [반음] 막대 양 끝: 기준에서 어두운 쪽·밝은 쪽으로 이만큼
    static let halfRangeSemitones = 6.0

    struct Reading: Equatable {
        /// [Hz] F2 중앙값
        let f2: Double
        /// 목소리가 높아 F1이 배음 쪽으로 끌렸을 수 있음 (모음 지도와 같은 규칙, VowelSpace)
        let isUncertain: Bool
    }

    /// `time` 직전 2.5초 동안 목소리와 포먼트가 잡힌 점들의 F2 중앙값. 점이 20개보다 적으면(무음이 길었으면) nil.
    static func current(_ readings: some Collection<PitchReading>, at time: TimeInterval) -> Reading? {
        let recent = readings.filter { $0.time > time - windowSeconds && $0.time <= time }
        let voiced = recent.compactMap { reading -> (f0: Double, formants: FormantAnalyzer.Estimate)? in
            guard let f0 = reading.frequency, let formants = reading.formants else { return nil }
            return (f0, formants)
        }
        guard voiced.count >= minimumPoints else { return nil }
        let f2 = PitchSummary.percentile(voiced.map(\.formants.f2.frequency).sorted(), 0.5)
        let f1 = PitchSummary.percentile(voiced.map(\.formants.f1.frequency).sorted(), 0.5)
        let f0 = PitchSummary.percentile(voiced.map(\.f0).sorted(), 0.5)
        return Reading(f2: f2, isUncertain: VowelSpace.isF1Uncertain(f1: f1, f0: f0))
    }

    /// 녹음(또는 기준 재기) 전체의 F2 중앙값 [Hz]. 목소리와 포먼트가 잡힌 점이 20개보다 적으면 nil.
    static func median(_ readings: some Collection<PitchReading>) -> Double? {
        let values = readings.compactMap { $0.frequency == nil ? nil : $0.formants?.f2.frequency }
        guard values.count >= minimumPoints else { return nil }
        return PitchSummary.percentile(values.sorted(), 0.5)
    }

    /// 기준 F2 대비 막대 위치 (0 어두운 끝, 0.5 기준, 1 밝은 끝). 반음 눈금이라 기준이 높든 낮든 같은 비율이 같은 거리다.
    static func position(f2: Double, baseline: Double) -> Double {
        let semitones = PitchScale.semitones(from: baseline, to: f2)
        return min(max(0.5 + semitones / (2 * halfRangeSemitones), 0), 1)
    }
}
