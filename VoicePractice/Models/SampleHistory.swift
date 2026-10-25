#if DEBUG
import Foundation
import SwiftData

/// 개발용 가짜 연습 기록. 시뮬레이터는 마이크 소리가 들어오지 않아 진짜 연습 기록을 만들 수 없어서, [기록] 탭을 확인할 때만 쓴다.
/// 실행 인자 `-seedSampleHistory YES`를 줄 때, 연습 기록이 하나도 없을 때만 넣는다. 출시용(Release) 빌드에는 들어가지 않는다.
extension PracticeArchive {
    static let seedArgumentKey = "seedSampleHistory"

    func seedSampleHistoryIfRequested(defaults: UserDefaults = .standard, now: Date = .now, calendar: Calendar = .current) {
        guard defaults.bool(forKey: Self.seedArgumentKey),
              (try? context.fetchCount(FetchDescriptor<PracticeSession>())) == 0 else { return }

        let today = calendar.startOfDay(for: now)
        // 40일 전부터 오늘까지, 사흘에 하루는 쉰다. 나흘마다 영어 발표 연습, 닷새마다 아침에도 한 번.
        for daysAgo in stride(from: 40, through: 0, by: -1) where daysAgo % 3 != 1 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let language: PracticeLanguage = daysAgo % 4 == 0 ? .english : .korean
            let median = 150 + Double(40 - daysAgo) * 0.4 + (language == .english ? 12 : 0) + sin(Double(daysAgo)) * 4
            addSample(at: day.addingTimeInterval(20 * 3600), minutes: 6 + Double(daysAgo % 5) * 3, median: median,
                      takes: 2 + daysAgo % 4, language: language)
            if daysAgo % 5 == 0 {
                addSample(at: day.addingTimeInterval(8 * 3600), minutes: 4, median: median - 6, takes: 1, language: .korean)
            }
        }
        for daysAgo in [38, 20, 3] {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let median = 148 + Double(40 - daysAgo) * 0.3
            saveBaseline(VoiceBaseline(median: median, low: median - 18, high: median + 22),
                         measuredAt: day.addingTimeInterval(19 * 3600))
        }
    }

    private func addSample(at start: Date, minutes: Double, median: Double, takes: Int, language: PracticeLanguage) {
        // 중앙값 ±20 Hz에 고르게 퍼진 높이 → 아래 10%·위 10%는 중앙값 ±16 Hz
        let voiced = (0..<100).map { median - 20 + 40 * Double($0) / 99 }
        let duration = minutes * 60
        guard let pitch = PitchSummary(voiced: voiced, voicedSeconds: duration * 0.4, duration: duration,
                                       target: TargetRangeStore.savedTarget(in: .standard)) else { return }
        saveSession(PracticeSessionLog.Summary(startedAt: start, endedAt: start.addingTimeInterval(duration),
                                               takeCount: takes, language: language, pitch: pitch))
    }
}
#endif
