import Foundation

/// 내 모음 지도: 7개 단모음을 하나씩 길게 냈을 때 잰 F1·F2.
/// 비교 대상은 이것뿐이다 (성별 평균표는 쓰지 않음, 원칙 3). 값은 기기 안(UserDefaults)에만 저장한다.
struct VowelMap: Codable, Equatable {
    /// 모음 하나를 잰 결과
    struct Entry: Codable, Equatable {
        /// [Hz] 중앙값
        let f1: Double
        let f2: Double
        /// [Hz] 아래 25%~위 25% — 길게 내는 동안 얼마나 흔들렸는지
        let f1Spread: ClosedRange<Double>
        let f2Spread: ClosedRange<Double>
        /// 잴 때 목소리가 높아 F1이 배음 쪽으로 끌렸을 수 있음
        let isF1Uncertain: Bool
        let measuredAt: Date
    }

    /// [s] 마이크로 모음 하나를 잴 때의 녹음 길이
    static let recordingSeconds: TimeInterval = 3
    /// [s] 포먼트가 이보다 짧게 잡히면 저장하지 않고 다시 재자고 한다
    static let minimumSeconds: TimeInterval = 1
    static let storageKey = "vowelMap"

    /// 모음 이름("아")별 결과
    private(set) var entries: [String: Entry] = [:]

    init() {}

    /// 저장된 값을 읽는다. 없거나 읽을 수 없으면 빈 지도.
    init(data: Data?) {
        guard let data, let map = try? JSONDecoder().decode(VowelMap.self, from: data) else { return }
        self = map
    }

    var data: Data? {
        try? JSONEncoder().encode(self)
    }

    subscript(vowel: KoreanVowel) -> Entry? {
        entries[vowel.rawValue]
    }

    /// 같은 모음을 다시 재면 새 값으로 바꾼다.
    mutating func set(_ entry: Entry, for vowel: KoreanVowel) {
        entries[vowel.rawValue] = entry
    }

    var measuredCount: Int {
        KoreanVowel.allCases.filter { self[$0] != nil }.count
    }

    /// 모음 하나를 길게 낸 기록으로 결과를 만든다. 포먼트가 잡힌 시간이 1초보다 짧으면 nil.
    /// 중앙값을 쓰므로 소리를 내기 시작하고 끝낼 때의 흔들림은 거의 영향을 주지 않는다.
    static func measure(_ readings: some Collection<PitchReading>, at date: Date = .now) -> Entry? {
        let all = Array(readings)
        let voiced = all.compactMap { reading -> (f0: Double, formants: FormantAnalyzer.Estimate)? in
            guard let f0 = reading.frequency, let formants = reading.formants else { return nil }
            return (f0, formants)
        }
        // 점 사이 간격(분석 간격)으로 포먼트가 잡힌 시간을 어림한다.
        let interval = all.count > 1 ? (all[all.count - 1].time - all[0].time) / Double(all.count - 1) : 0
        guard Double(voiced.count) * interval >= minimumSeconds else { return nil }

        let f1s = voiced.map(\.formants.f1.frequency).sorted()
        let f2s = voiced.map(\.formants.f2.frequency).sorted()
        let f1 = PitchSummary.percentile(f1s, 0.5)
        let f0 = PitchSummary.percentile(voiced.map(\.f0).sorted(), 0.5)
        return Entry(
            f1: f1,
            f2: PitchSummary.percentile(f2s, 0.5),
            f1Spread: PitchSummary.percentile(f1s, 0.25)...PitchSummary.percentile(f1s, 0.75),
            f2Spread: PitchSummary.percentile(f2s, 0.25)...PitchSummary.percentile(f2s, 0.75),
            isF1Uncertain: VowelSpace.isF1Uncertain(f1: f1, f0: f0),
            measuredAt: date
        )
    }
}
