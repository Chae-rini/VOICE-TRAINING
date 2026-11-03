import Foundation
import SwiftData
import Testing
@testable import VoicePractice

/// 녹음마다 읽은 대본을 남겨, 같은 대본끼리 공명 밝기를 견주기 (2026-11-03)
@MainActor
struct TakeScriptTests {
    private let morning = TakeScript(id: "dialogue-01", title: "새벽 첫차")
    private let umbrella = TakeScript(id: "my-1234", title: "우산 빌려주기")

    /// `from` [s]부터 0.02초 간격의 점 `count`개. `voiced`가 false인 점은 무음, `f2`가 nil이면 포먼트 없음
    private func readings(from time: TimeInterval, count: Int, f2: Double? = 1500,
                          voiced: (Int) -> Bool = { _ in true }) -> [PitchReading] {
        (0..<count).map { index in
            let formants = f2.map {
                FormantAnalyzer.Estimate(f1: Formant(frequency: 600, bandwidth: 80), f2: Formant(frequency: $0, bandwidth: 120))
            }
            let isVoiced = voiced(index)
            return PitchReading(time: time + Double(index) * 0.02, frequency: isVoiced ? 180 : nil,
                                formants: isVoiced ? formants : nil)
        }
    }

    // MARK: - 녹음 하나가 읽은 대본 정하기

    @Test("녹음이 시작된 뒤라도 말하기 전에 넘긴 대본이면 넘긴 대본을 읽은 녹음이다")
    func switchBeforeSpeaking() {
        var timeline = ScriptTimeline()
        timeline.show(morning, at: 0)
        timeline.forget(before: 10)  // 10초에 녹음 시작
        timeline.show(umbrella, at: 12)
        // 10~12초는 조용하고, 12초 조금 뒤부터 읽는다
        let take = readings(from: 10, count: 500, voiced: { $0 > 100 })
        #expect(timeline.script(for: take) == umbrella)
    }

    @Test("읽는 도중에 대본을 넘기면 두 대본이 섞여 대본을 남기지 않는다")
    func switchWhileReading() {
        var timeline = ScriptTimeline()
        timeline.show(morning, at: 0)
        timeline.show(umbrella, at: 15)
        // 10~20초 내내 목소리: 절반씩
        #expect(timeline.script(for: readings(from: 10, count: 500)) == nil)
    }

    @Test("넘기기 전에 짧게 낸 소리는 견디고(목소리의 90% 이상이면 그 대본), 넘으면 남기지 않는다")
    func toleratesShortSound() {
        var timeline = ScriptTimeline()
        timeline.show(morning, at: 0)
        timeline.show(umbrella, at: 11)
        // 목소리 점 100개 중 10개(10~10.2초)가 앞 대본 → 90%는 새 대본
        let mostly = readings(from: 10, count: 50, voiced: { $0 < 10 }) + readings(from: 11, count: 90)
        #expect(timeline.script(for: mostly) == umbrella)
        // 11개가 앞 대본이면 새 대본이 90%에 못 미친다
        let mixed = readings(from: 10, count: 50, voiced: { $0 < 11 }) + readings(from: 11, count: 89)
        #expect(timeline.script(for: mixed) == nil)
        #expect(ScriptTimeline.minimumShare == 0.9)
    }

    @Test("대본이 아닌 문장을 보며 말했거나, 목소리가 없거나, 대본을 알리기 전이면 대본이 없다")
    func noScript() {
        var timeline = ScriptTimeline()
        #expect(timeline.script(for: readings(from: 0, count: 100)) == nil)
        timeline.show(morning, at: 0)
        timeline.show(nil, at: 5)  // 내 문장으로 바꿈
        #expect(timeline.script(for: readings(from: 10, count: 100)) == nil)
        #expect(timeline.script(for: readings(from: 1, count: 100, voiced: { _ in false })) == nil)
        #expect(timeline.script(for: readings(from: 1, count: 100)) == morning)
    }

    @Test("새 녹음을 시작하며 앞의 바뀜을 잊어도, 그때 화면에 있던 대본은 남는다")
    func forgetKeepsCurrent() {
        var timeline = ScriptTimeline()
        timeline.show(morning, at: 0)
        timeline.show(umbrella, at: 5)
        timeline.show(umbrella, at: 6)  // 같은 대본을 다시 알려도 바뀌지 않는다
        timeline.forget(before: 20)
        #expect(timeline.script(at: 20) == umbrella)
        #expect(timeline.script(for: readings(from: 20, count: 100)) == umbrella)
    }

    // MARK: - 연습 기록에 남기기

    @Test("녹음마다 읽은 대본과 그 녹음의 F2 중앙값을 남긴다 (포먼트가 모자라면 F2는 없다)")
    func recordsScriptAndF2() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var log = PracticeSessionLog(startedAt: start, language: .korean)
        log.beginTake()
        let first = readings(from: 0, count: 300, f2: 1450)
        log.add(first)
        log.finishTake(readings: first, duration: 6, target: nil, script: morning, at: start.addingTimeInterval(10))
        log.beginTake()
        let second = readings(from: 20, count: 300, f2: nil)
        log.add(second)
        log.finishTake(readings: second, duration: 6, target: nil, at: start.addingTimeInterval(30))

        let summary = try #require(log.finish(at: start.addingTimeInterval(40), target: nil))
        #expect(summary.takes[0].script == morning)
        #expect(summary.takes[0].f2Median == 1450)
        #expect(summary.takes[1].script == nil)
        #expect(summary.takes[1].f2Median == nil)
    }

    @Test("AI 요청문의 녹음 줄에 읽은 대본 제목이 들어간다 (대본이 없으면 그대로)")
    func requestLineHasTitle() {
        let pitch = PitchSummary(duration: 60, voicedSeconds: 25, median: 182, p10: 165, p90: 201,
                                 target: nil, inTargetFraction: nil)
        let take = PracticeSessionLog.Take(round: 2, endedAt: .now, pitch: pitch, script: morning, f2Median: 1500)
        #expect(take.requestLine(sessionTarget: nil)
                == "- 2번째 녹음 (1분, 목소리 25.0초, 대본 ‘새벽 첫차’): 중앙 182 Hz, 범위 165~201 Hz")
        let plain = PracticeSessionLog.Take(round: 2, endedAt: .now, pitch: pitch)
        #expect(plain.requestLine(sessionTarget: nil) == "- 2번째 녹음 (1분, 목소리 25.0초): 중앙 182 Hz, 범위 165~201 Hz")
    }

    @Test("읽은 대본과 녹음의 F2는 연습 기록과 함께 남고, 그래프에는 둘 다 남은 녹음만 나온다")
    func savesAndReadsBack() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString)")
        let archive = PracticeArchive(inMemory: true, recordingsDirectory: directory)
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var log = PracticeSessionLog(startedAt: start, language: .english)
        for (index, script, f2) in [(0, morning, 1450.0), (1, nil, 1500.0), (2, umbrella, nil)] as [(Int, TakeScript?, Double?)] {
            log.beginTake()
            let take = readings(from: Double(index) * 20, count: 300, f2: f2)
            log.add(take)
            log.finishTake(readings: take, duration: 6, target: nil, script: script,
                           at: start.addingTimeInterval(Double(index + 1) * 10))
        }
        let summary = try #require(log.finish(at: start.addingTimeInterval(60), target: nil))
        try archive.saveSession(summary)

        let session = try #require(try archive.context.fetch(FetchDescriptor<PracticeSession>()).first)
        #expect(session.summary.takes == summary.takes)
        #expect(ScriptTakePoint.points(session) == [
            ScriptTakePoint(endedAt: start.addingTimeInterval(10), script: morning, f2: 1450, language: .english),
        ])
    }

    // MARK: - [기록] 그래프

    private func point(_ endedAt: Date, _ script: TakeScript, f2: Double = 1500,
                       language: PracticeLanguage = .korean) -> ScriptTakePoint {
        ScriptTakePoint(endedAt: endedAt, script: script, f2: f2, language: language)
    }

    @Test("고를 대본: 많이 읽은 순, 같으면 최근에 읽은 순, 제목은 가장 최근 것")
    func choices() {
        let day: TimeInterval = 86_400
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let renamed = TakeScript(id: morning.id, title: "새벽 첫차 (고침)")
        let other = TakeScript(id: "essay-02", title: "골목 빵집")
        let takes = [
            point(base, morning), point(base.addingTimeInterval(day), renamed),
            point(base.addingTimeInterval(2 * day), umbrella),
            point(base.addingTimeInterval(3 * day), other),
        ]
        #expect(PracticeHistory.scriptChoices(takes) == [
            ScriptChoice(script: renamed, takeCount: 2),
            ScriptChoice(script: other, takeCount: 1),
            ScriptChoice(script: umbrella, takeCount: 1),
        ])
        #expect(PracticeHistory.scriptChoices([]).isEmpty)
    }

    @Test("대본을 읽은 녹음도 기간과 언어로 거르고, 세로축은 고른 녹음의 F2와 기준으로 잡는다")
    func filtersAndDomain() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 21))!
        let recent = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 20))!
        let old = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 20))!
        let takes = [point(recent, morning, f2: 1400), point(recent.addingTimeInterval(60), morning, f2: 2100, language: .english),
                     point(old, morning)]
        #expect(PracticeHistory.filter(takes, period: .week, language: nil, now: now, calendar: calendar) == Array(takes[0...1]))
        #expect(PracticeHistory.filter(takes, period: .all, language: .korean, now: now, calendar: calendar)
                == [takes[0], takes[2]])

        let domain = PracticeHistory.resonanceDomain(Array(takes[0...1]), baseline: 1500)
        #expect(abs(PitchScale.semitones(from: domain.lowerBound, to: 1400) - 1.5) < 1e-9)
        #expect(abs(PitchScale.semitones(from: 2100, to: domain.upperBound) - 1.5) < 1e-9)
    }
}
