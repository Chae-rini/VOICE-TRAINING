import Foundation
import SwiftData

/// 연습할 때 말한 언어. 기록에 함께 남겨, 언어마다 목소리 높이가 어떻게 다른지 나중에 비교할 수 있게 한다.
/// 화면 글자는 한국어 그대로이고(원칙 5), 언어는 기록에만 붙는다.
enum PracticeLanguage: String, CaseIterable, Identifiable {
    case korean = "ko"
    case english = "en"
    case japanese = "ja"
    case other = "other"

    static let storageKey = "practiceLanguage"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .korean: "한국어"
        case .english: "영어"
        case .japanese: "일본어"
        case .other: "기타"
        }
    }
}

/// 연습 한 번(‘반복 루프 재생’부터 정지까지) 동안, 녹음 여러 번에 걸쳐 잡힌 목소리 높이를 모은다.
/// 소리는 모으지 않고 숫자만 모은다. 정지하면 `PracticeSession` 기록 하나가 된다.
struct PracticeSessionLog {
    /// [s] 이보다 짧은 연습은 남기지 않는다 (잘못 눌렀다 바로 멈춘 경우 등)
    static let minimumSeconds: TimeInterval = 30
    /// [s] 목소리가 이보다 짧게 잡힌 연습은 남기지 않는다
    static let minimumVoicedSeconds: TimeInterval = 5
    /// [s] 이웃한 점 사이가 이보다 벌어지면 그 사이는 목소리 시간으로 세지 않는다 (분석 간격은 약 0.02초)
    static let maxReadingGap: TimeInterval = 0.1

    /// 정지했을 때 남길 내용
    struct Summary: Equatable {
        let startedAt: Date
        let endedAt: Date
        /// 녹음한 횟수 (듣기 뒤 다시 녹음할 때마다 1씩)
        let takeCount: Int
        let language: PracticeLanguage
        /// 연습 전체를 하나로 모은 피치 요약. `duration`은 시작~정지 시간
        let pitch: PitchSummary
    }

    let startedAt: Date
    let language: PracticeLanguage
    private(set) var takeCount = 0
    /// [Hz] 잡힌 목소리 높이들
    private(set) var voiced: [Double] = []
    /// [s] 목소리가 잡힌 시간
    private(set) var voicedSeconds: TimeInterval = 0
    /// [s] 바로 앞 점의 시각. 녹음을 새로 시작하면 지운다 (녹음 사이의 빈 시간을 목소리로 세지 않게).
    private var lastTime: TimeInterval?

    init(startedAt: Date = .now, language: PracticeLanguage) {
        self.startedAt = startedAt
        self.language = language
    }

    /// 녹음을 새로 시작할 때 부른다 (처음, 그리고 듣기 뒤 다시 녹음할 때마다).
    mutating func beginTake() {
        takeCount += 1
        lastTime = nil
    }

    /// 녹음 중에 들어온 피치 점들을 더한다. 목소리가 잡힌 점마다 앞 점과의 간격만큼을 목소리 시간으로 센다.
    mutating func add(_ readings: some Sequence<PitchReading>) {
        for reading in readings {
            if let frequency = reading.frequency {
                voiced.append(frequency)
                if let lastTime {
                    voicedSeconds += min(max(reading.time - lastTime, 0), Self.maxReadingGap)
                }
            }
            lastTime = reading.time
        }
    }

    /// 정지했을 때의 요약. 30초보다 짧은 연습이거나 목소리가 5초보다 짧게 잡혔으면 nil (남기지 않음).
    func finish(at endedAt: Date, target: ClosedRange<Double>?) -> Summary? {
        let duration = endedAt.timeIntervalSince(startedAt)
        guard duration >= Self.minimumSeconds, voicedSeconds >= Self.minimumVoicedSeconds,
              let pitch = PitchSummary(voiced: voiced, voicedSeconds: voicedSeconds, duration: duration, target: target) else {
            return nil
        }
        return Summary(startedAt: startedAt, endedAt: endedAt, takeCount: takeCount, language: language, pitch: pitch)
    }
}

// MARK: - 저장하는 기록 (SwiftData, 기기 안에만)

/// 연습 한 번의 요약. 정지하면 자동으로 남는다. 소리는 없고 숫자만 있다.
@Model
final class PracticeSession {
    var startedAt: Date
    var endedAt: Date
    var takeCount: Int
    /// [s] 목소리가 잡힌 시간
    var voicedSeconds: Double
    /// [Hz] 피치 중앙값, 아래 10%, 위 10%
    var medianHz: Double
    var lowHz: Double
    var highHz: Double
    /// [Hz] 그때의 목표 범위. 정하지 않았으면 nil
    var targetLowerHz: Double?
    var targetUpperHz: Double?
    /// 0~1. 목표 범위 안에 있던 비율
    var inTargetFraction: Double?
    /// `PracticeLanguage`의 rawValue
    var languageCode: String

    init(_ summary: PracticeSessionLog.Summary) {
        startedAt = summary.startedAt
        endedAt = summary.endedAt
        takeCount = summary.takeCount
        voicedSeconds = summary.pitch.voicedSeconds
        medianHz = summary.pitch.median
        lowHz = summary.pitch.p10
        highHz = summary.pitch.p90
        targetLowerHz = summary.pitch.target?.lowerBound
        targetUpperHz = summary.pitch.target?.upperBound
        inTargetFraction = summary.pitch.inTargetFraction
        languageCode = summary.language.rawValue
    }

    var language: PracticeLanguage {
        PracticeLanguage(rawValue: languageCode) ?? .other
    }

    /// [s] 시작~정지 시간 (듣기·숨 고르기 포함)
    var practiceSeconds: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}

/// 사용자가 ‘기록에 남기기’를 누른 녹음. 소리는 `PracticeArchive`가 Documents/Recordings에 m4a로 저장한다.
@Model
final class SavedRecording {
    var recordedAt: Date
    /// 불러온 파일의 이름. 앱에서 방금 녹음한 것이면 빈 글자
    var title: String
    var memo: String
    /// Recordings 폴더 안의 파일 이름
    var fileName: String
    /// [s]
    var durationSeconds: Double
    var voicedSeconds: Double
    /// [Hz]
    var medianHz: Double
    var lowHz: Double
    var highHz: Double
    var targetLowerHz: Double?
    var targetUpperHz: Double?
    var inTargetFraction: Double?
    var languageCode: String

    init(summary: PitchSummary, title: String, memo: String, fileName: String,
         language: PracticeLanguage, recordedAt: Date) {
        self.recordedAt = recordedAt
        self.title = title
        self.memo = memo
        self.fileName = fileName
        durationSeconds = summary.duration
        voicedSeconds = summary.voicedSeconds
        medianHz = summary.median
        lowHz = summary.p10
        highHz = summary.p90
        targetLowerHz = summary.target?.lowerBound
        targetUpperHz = summary.target?.upperBound
        inTargetFraction = summary.inTargetFraction
        languageCode = language.rawValue
    }

    var language: PracticeLanguage {
        PracticeLanguage(rawValue: languageCode) ?? .other
    }
}

/// ‘내 목소리 재기’를 저장할 때마다 하나씩 쌓인다. 지금 쓰는 기준은 그대로 UserDefaults(TargetRangeStore)에 있다.
@Model
final class BaselineRecord {
    var measuredAt: Date
    /// [Hz]
    var medianHz: Double
    var lowHz: Double
    var highHz: Double

    init(_ baseline: VoiceBaseline, measuredAt: Date) {
        self.measuredAt = measuredAt
        medianHz = baseline.median
        lowHz = baseline.low
        highHz = baseline.high
    }
}

/// 내 모음 지도에서 모음 하나를 잴 때마다 하나씩 쌓인다. 지도에는 모음마다 마지막 값만 보인다(VowelMap).
@Model
final class VowelRecord {
    var measuredAt: Date
    /// `KoreanVowel`의 rawValue ("아" 등)
    var vowel: String
    /// [Hz] 중앙값과 길게 내는 동안 흔들린 범위(25%~75%)
    var f1: Double
    var f2: Double
    var f1Low: Double
    var f1High: Double
    var f2Low: Double
    var f2High: Double
    var isF1Uncertain: Bool

    init(_ entry: VowelMap.Entry, vowel: KoreanVowel) {
        measuredAt = entry.measuredAt
        self.vowel = vowel.rawValue
        f1 = entry.f1
        f2 = entry.f2
        f1Low = entry.f1Spread.lowerBound
        f1High = entry.f1Spread.upperBound
        f2Low = entry.f2Spread.lowerBound
        f2High = entry.f2Spread.upperBound
        isF1Uncertain = entry.isF1Uncertain
    }
}
