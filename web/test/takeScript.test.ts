import { describe, expect, it } from 'vitest'
import type { PitchReading } from '../src/dsp/pitchHistory'
import { semitones } from '../src/dsp/pitchScale'
import { PitchSummary } from '../src/dsp/pitchSummary'
import {
  filterScriptTakes,
  scriptChoices,
  scriptTakePoints,
  takeResonanceDomain,
  type ScriptTakePoint,
} from '../src/model/history'
import { isSessionRecord, type PracticeLanguage, type SessionRecord } from '../src/model/records'
import { sampleRecords } from '../src/model/sampleHistory'
import { ScriptTimeline, takeScriptOf, type TakeScript } from '../src/model/takeScript'
import {
  PracticeSessionLog,
  sessionFeedbackRequest,
  sessionRecord,
  sessionSummaryOf,
  takeRequestLine,
} from '../src/practice/sessionLog'
import { encodeRecordsFile, EMPTY_RECORDS, parseRecordsFile } from '../src/storage/archive'

// iOS VoicePracticeTests/TakeScriptTests.swift를 옮겼다 (같은 경우, 같은 글). 녹음마다 읽은 대본을 남겨, 같은 대본끼리 공명 밝기를 견주기.

const morning: TakeScript = { id: 'dialogue-01', title: '새벽 첫차' }
const umbrella: TakeScript = { id: 'my-1234', title: '우산 빌려주기' }

/** `from` [s]부터 0.02초 간격의 점 `count`개. `voiced`가 false인 점은 무음, `f2`가 null이면 포먼트 없음 */
function readings(from: number, count: number, f2: number | null = 1500, voiced: (i: number) => boolean = () => true): PitchReading[] {
  return Array.from({ length: count }, (_, i) => {
    const isVoiced = voiced(i)
    const formants = f2 === null ? null : { f1: { frequency: 600, bandwidth: 80 }, f2: { frequency: f2, bandwidth: 120 } }
    return { time: from + i * 0.02, frequency: isVoiced ? 180 : null, formants: isVoiced ? formants : null }
  })
}

describe('녹음 하나가 읽은 대본 정하기 (ScriptTimeline)', () => {
  it('녹음이 시작된 뒤라도 말하기 전에 넘긴 대본이면 넘긴 대본을 읽은 녹음이다', () => {
    const timeline = new ScriptTimeline()
    timeline.show(morning, 0)
    timeline.restart() // 10초에 녹음 시작
    timeline.show(umbrella, 12)
    // 10~12초는 조용하고, 12초 조금 뒤부터 읽는다
    const take = readings(10, 500, 1500, (i) => i > 100)
    expect(timeline.scriptFor(take)).toEqual(umbrella)
  })

  it('읽는 도중에 대본을 넘기면 두 대본이 섞여 대본을 남기지 않는다', () => {
    const timeline = new ScriptTimeline()
    timeline.show(morning, 0)
    timeline.show(umbrella, 15)
    // 10~20초 내내 목소리: 절반씩
    expect(timeline.scriptFor(readings(10, 500))).toBeNull()
  })

  it('넘기기 전에 짧게 낸 소리는 견디고(목소리의 90% 이상이면 그 대본), 넘으면 남기지 않는다', () => {
    const timeline = new ScriptTimeline()
    timeline.show(morning, 0)
    timeline.show(umbrella, 11)
    // 목소리 점 100개 중 10개(10~10.2초)가 앞 대본 → 90%는 새 대본
    const mostly = [...readings(10, 50, 1500, (i) => i < 10), ...readings(11, 90)]
    expect(timeline.scriptFor(mostly)).toEqual(umbrella)
    // 11개가 앞 대본이면 새 대본이 90%에 못 미친다
    const mixed = [...readings(10, 50, 1500, (i) => i < 11), ...readings(11, 89)]
    expect(timeline.scriptFor(mixed)).toBeNull()
    expect(ScriptTimeline.minimumShare).toBe(0.9)
  })

  it('대본이 아닌 문장을 보며 말했거나, 목소리가 없거나, 대본을 알리기 전이면 대본이 없다', () => {
    const timeline = new ScriptTimeline()
    expect(timeline.scriptFor(readings(0, 100))).toBeNull()
    timeline.show(morning, 0)
    timeline.show(null, 5) // 내 문장으로 바꿈
    expect(timeline.scriptFor(readings(10, 100))).toBeNull()
    expect(timeline.scriptFor(readings(1, 100, 1500, () => false))).toBeNull()
    expect(timeline.scriptFor(readings(1, 100))).toEqual(morning)
  })

  it('새 녹음을 시작하며 앞의 바뀜을 잊어도, 그때 화면에 있던 대본은 남는다', () => {
    const timeline = new ScriptTimeline()
    timeline.show(morning, 0)
    timeline.show(umbrella, 5)
    timeline.show({ ...umbrella }, 6) // 같은 대본을 다시 알려도 바뀌지 않는다
    timeline.restart()
    expect(timeline.scriptAt(20)).toEqual(umbrella)
    expect(timeline.scriptFor(readings(20, 100))).toEqual(umbrella)
  })

  it('(웹만) 마이크를 켜기 전에 다른 시계로 적은 대본도, 녹음을 시작하면 녹음 처음부터 화면에 있던 대본이다', () => {
    const timeline = new ScriptTimeline()
    // 마이크를 켜기 전에는 소리 시계가 없어 performance.now()로 적는다 (큰 수). 소리 시계는 0부터 센다
    timeline.show(morning, 5000)
    timeline.restart()
    expect(timeline.scriptFor(readings(0.5, 300))).toEqual(morning)
    // 녹음 중에 넘긴 대본은 소리 시계로 적는다
    timeline.show(umbrella, 0.5 + 300 * 0.02)
    timeline.restart()
    expect(timeline.scriptFor(readings(8, 300))).toEqual(umbrella)
  })
})

describe('연습 기록에 대본·F2 남기기', () => {
  const start = new Date(1_800_000_000_000)
  const at = (seconds: number) => new Date(start.getTime() + seconds * 1000)

  it('녹음마다 읽은 대본과 그 녹음의 F2 중앙값을 남긴다 (포먼트가 모자라면 F2는 없다)', () => {
    const log = new PracticeSessionLog(start, 'ko')
    log.beginTake()
    const first = readings(0, 300, 1450)
    log.add(first)
    log.finishTake(first, 6, null, at(10), undefined, morning)
    log.beginTake()
    const second = readings(20, 300, null)
    log.add(second)
    log.finishTake(second, 6, null, at(30))

    const summary = log.finish(at(40), null)!
    expect(summary.takes[0].script).toEqual(morning)
    expect(summary.takes[0].f2Median).toBe(1450)
    expect(summary.takes[1].script).toBeUndefined()
    expect(summary.takes[1].f2Median).toBeUndefined()
  })

  it('AI 요청문의 녹음 줄에 읽은 대본 제목이 들어간다 (대본이 없으면 그대로)', () => {
    const pitch = new PitchSummary(60, 25, 182, 165, 201, null, null)
    expect(takeRequestLine({ round: 2, endedAt: start, pitch, script: morning, f2Median: 1500 }, null)).toBe(
      '- 2번째 녹음 (1분, 목소리 25.0초, 대본 ‘새벽 첫차’): 중앙 182 Hz, 범위 165~201 Hz',
    )
    expect(takeRequestLine({ round: 2, endedAt: start, pitch }, null)).toBe(
      '- 2번째 녹음 (1분, 목소리 25.0초): 중앙 182 Hz, 범위 165~201 Hz',
    )
  })

  it('읽은 대본과 녹음의 F2는 연습 기록과 함께 남고, 그래프에는 둘 다 남은 녹음만 나온다', () => {
    const log = new PracticeSessionLog(start, 'en')
    const cases: [TakeScript | null, number | null][] = [
      [morning, 1450],
      [null, 1500],
      [umbrella, null],
    ]
    cases.forEach(([script, f2], index) => {
      log.beginTake()
      const take = readings(index * 20, 300, f2)
      log.add(take)
      log.finishTake(take, 6, null, at((index + 1) * 10), undefined, script)
    })
    const summary = log.finish(at(60), null)!
    const record = sessionRecord(summary, 'id')

    // 기록 파일에 쓰고 다시 읽어도 같다
    const read = parseRecordsFile(encodeRecordsFile({ ...EMPTY_RECORDS, sessions: [record] }, at(70)))
    const back = read.ok ? (read.value.sessions[0] as SessionRecord) : null
    expect(back).toEqual(record)
    expect(sessionSummaryOf(back!).takes).toEqual(summary.takes)
    expect(scriptTakePoints(back!)).toEqual([{ endedAt: at(10), script: morning, f2: 1450, language: 'en' }])
    // 요청문에도 대본 제목
    expect(sessionFeedbackRequest(summary)).toContain('- 1번째 녹음 (6초, 목소리 6.0초, 대본 ‘새벽 첫차’)')
  })

  it('대본·F2 칸이 없는 예전 기록도, 모양이 다른 칸도 기록은 그대로 읽고 대본·F2만 없는 것으로 본다', () => {
    const base = sessionRecord(
      {
        startedAt: start,
        endedAt: at(60),
        takeCount: 1,
        language: 'ko',
        pitch: new PitchSummary(60, 25, 182, 165, 201, null, null),
        takes: [{ round: 1, endedAt: at(30), pitch: new PitchSummary(30, 20, 180, 170, 190, null, null) }],
        f2Median: null,
      },
      'old',
    )
    expect(base.takes[0]).not.toHaveProperty('script')
    expect(base.takes[0]).not.toHaveProperty('f2Median')
    const odd = { ...base, takes: [{ ...base.takes[0], script: '새벽 첫차', f2Median: 'x' }] }
    expect(isSessionRecord(odd)).toBe(true)
    expect(sessionSummaryOf(odd as unknown as SessionRecord).takes[0]).not.toHaveProperty('script')
    expect(scriptTakePoints(odd as unknown as SessionRecord)).toEqual([])
    expect(takeScriptOf({ id: 'a' })).toBeNull()
    expect(takeScriptOf({ id: 'a', title: '가' })).toEqual({ id: 'a', title: '가' })
  })
})

describe('[기록] 같은 대본 고르기', () => {
  const point = (endedAt: Date, script: TakeScript, f2 = 1500, language: PracticeLanguage = 'ko'): ScriptTakePoint => ({
    endedAt,
    script,
    f2,
    language,
  })

  it('고를 대본: 많이 읽은 순, 같으면 최근에 읽은 순, 제목은 가장 최근 것', () => {
    const day = 86_400_000
    const base = new Date(1_800_000_000_000)
    const later = (days: number) => new Date(base.getTime() + days * day)
    const renamed: TakeScript = { id: morning.id, title: '새벽 첫차 (고침)' }
    const other: TakeScript = { id: 'essay-02', title: '골목 빵집' }
    const takes = [point(base, morning), point(later(1), renamed), point(later(2), umbrella), point(later(3), other)]
    expect(scriptChoices(takes)).toEqual([
      { script: renamed, takeCount: 2 },
      { script: other, takeCount: 1 },
      { script: umbrella, takeCount: 1 },
    ])
    expect(scriptChoices([])).toEqual([])
  })

  it('대본을 읽은 녹음도 기간과 언어로 거르고, 세로축은 고른 녹음의 F2와 기준으로 잡는다', () => {
    const now = new Date(2026, 10, 3, 21)
    const recent = new Date(2026, 10, 1, 20)
    const old = new Date(2026, 9, 1, 20)
    const takes = [point(recent, morning, 1400), point(new Date(recent.getTime() + 60_000), morning, 2100, 'en'), point(old, morning)]
    expect(filterScriptTakes(takes, 'week', null, now)).toEqual(takes.slice(0, 2))
    expect(filterScriptTakes(takes, 'all', 'ko', now)).toEqual([takes[0], takes[2]])

    const domain = takeResonanceDomain(takes.slice(0, 2), 1500)
    expect(semitones(domain.lower, 1400)).toBeCloseTo(1.5, 9)
    expect(semitones(2100, domain.upper)).toBeCloseTo(1.5, 9)
  })

  it('가짜 기록: F2가 남는 연습의 녹음은 앞의 대본 셋 중 하나를 읽고(4번째 녹음은 대본 없음), 대본마다 F2가 다르다', () => {
    const records = sampleRecords(new Date(2026, 10, 3, 21), null)
    const sessions = records.sessions as SessionRecord[]
    const points = sessions.flatMap(scriptTakePoints)
    const choices = scriptChoices(points)
    expect(choices).toHaveLength(3)
    expect(points.length).toBeGreaterThan(30)
    // 4번째 녹음과 F2가 없는 연습(30일보다 전)에는 대본이 없다
    for (const session of sessions) {
      for (const take of session.takes) {
        if (take.round === 4 || session.f2Median === null) expect(take.script).toBeUndefined()
      }
    }
  })
})
