import { describe, expect, it } from 'vitest'
import { semitones } from '../src/dsp/pitchScale'
import { PitchSummary } from '../src/dsp/pitchSummary'
import { range } from '../src/dsp/range'
import { dayTicks, markerPath, minuteTicks, timeX } from '../src/graph/historyChart'
import {
  dailyPractice,
  dateDomain,
  filterPoints,
  historyTotals,
  periodContains,
  periodStart,
  pitchDomain,
  sessionPitchDomain,
  totalLabel,
  type SessionPoint,
} from '../src/model/history'
import { isBaselineRecord, isSessionRecord, readableRecords, type PracticeLanguage } from '../src/model/records'
import { sampleRecords } from '../src/model/sampleHistory'
import {
  PracticeSessionLog,
  sessionFeedbackRequest,
  sessionRecord,
  sessionSummaryOf,
  takeNumbersLine,
  type SessionSummary,
} from '../src/practice/sessionLog'
import { EMPTY_RECORDS } from '../src/storage/archive'

// iOS VoicePracticeTests/PracticeHistoryTests.swift와 PracticeRecordTests의 요청문 테스트를 옮겼다.
// 날짜는 이 기기의 시간대로 센다 (테스트도 같은 시간대의 날짜를 만든다).

/** 2026-10-25 21:00 */
const now = new Date(2026, 9, 25, 21)
const date = (day: number, hour: number, month = 10) => new Date(2026, month - 1, day, hour)

function point(start: Date, { minutes = 10, median = 160, low = 140, high = 185, language = 'ko' as PracticeLanguage } = {}): SessionPoint {
  return { startedAt: start, practiceSeconds: minutes * 60, median, low, high, language }
}

describe('PracticeHistory ([기록]의 계산)', () => {
  it('기간: 7일은 오늘과 그 앞 6일, 30일은 오늘과 그 앞 29일, 전체는 처음부터', () => {
    expect(periodStart('week', now)).toEqual(date(19, 0))
    expect(periodStart('month', now)).toEqual(date(26, 0, 9))
    expect(periodStart('all', now)).toBeNull()
    expect(periodContains('week', date(19, 0), now)).toBe(true)
    expect(periodContains('week', date(18, 23), now)).toBe(false)
    expect(periodContains('all', date(1, 0, 1), now)).toBe(true)
  })

  it('기간과 언어로 거른다', () => {
    const points = [
      point(date(25, 20)),
      point(date(24, 20), { language: 'en' }),
      point(date(10, 20)),
      point(date(10, 8), { language: 'ja' }),
    ]
    expect(filterPoints(points, 'week', null, now)).toHaveLength(2)
    expect(filterPoints(points, 'week', 'en', now)).toEqual([points[1]])
    expect(filterPoints(points, 'all', 'ko', now)).toEqual([points[0], points[2]])
  })

  it('하루에 여러 번 연습하면 그날 시간을 더하고, 자정을 넘긴 연습은 시작한 날로 센다', () => {
    const points = [
      point(date(24, 8), { minutes: 5 }),
      point(date(24, 20), { minutes: 12 }),
      point(new Date(2026, 9, 25, 23, 30), { minutes: 40 }), // 25일 23:30 시작 → 26일 0:10 끝
    ]
    expect(dailyPractice(points)).toEqual([
      { day: date(24, 0), minutes: 17 },
      { day: date(25, 0), minutes: 40 },
    ])
  })

  it('모아 보기: 연습 횟수, 연습한 날 수(연속 여부는 따지지 않음), 모두 합친 시간', () => {
    const points = [point(date(20, 20), { minutes: 10 }), point(date(20, 21), { minutes: 5 }), point(date(25, 8), { minutes: 30 })]
    expect(historyTotals(points)).toEqual({ sessionCount: 3, dayCount: 2, practiceSeconds: 45 * 60 })
    expect(historyTotals([])).toEqual({ sessionCount: 0, dayCount: 0, practiceSeconds: 0 })
  })

  it('가로축: 기간 첫날 0시 ~ 내일 0시, 전체는 가장 이른 연습한 날부터', () => {
    const points = [point(date(3, 20, 8)), point(date(25, 8))]
    expect(dateDomain(points, 'week', now)).toEqual({ start: date(19, 0), end: date(26, 0) })
    expect(dateDomain(points, 'all', now)).toEqual({ start: date(3, 0, 8), end: date(26, 0) })
    expect(dateDomain([], 'all', now)).toEqual({ start: date(19, 0), end: date(26, 0) })
  })

  it('세로축(반음 눈금): 연습 범위·목표 범위·기준이 모두 들어가고, 위아래 반음 1.5개 여유, 70~400 Hz 안, 최소 반음 6개 폭', () => {
    const points = [point(now, { low: 140, high: 185 }), point(now, { low: 150, high: 210 })]
    // 가장 낮은 값 140, 가장 높은 값은 목표 상한 230 → 위아래로 반음 1.5개씩 여유
    const domain = sessionPitchDomain(points, range(190, 230), 165)
    expect(semitones(domain.lower, 140)).toBeCloseTo(1.5, 9)
    expect(semitones(230, domain.upper)).toBeCloseTo(1.5, 9)

    // 폭이 좁으면 가운데(반음 눈금의 가운데)를 두고 반음 6개로 넓힌다
    const narrow = sessionPitchDomain([point(now, { low: 200, high: 210 })], null, null)
    expect(semitones(narrow.lower, narrow.upper)).toBeCloseTo(6, 9)
    expect(semitones(narrow.lower, 200)).toBeCloseTo(semitones(210, narrow.upper), 9)

    // 아래 끝을 넘으면 안쪽으로 민다 (반음 폭은 그대로)
    const low = sessionPitchDomain([point(now, { low: 75, high: 100 })], null, null)
    expect(low.lower).toBe(70)
    expect(low.upper).toBeGreaterThanOrEqual(100)
    expect(semitones(70, low.upper) - semitones(75, 100)).toBeCloseTo(3, 9)

    // 위 끝
    const high = sessionPitchDomain([point(now, { low: 360, high: 395 })], null, null)
    expect(high.upper).toBe(400)
    expect(semitones(high.lower, 400)).toBeCloseTo(6, 9)

    // 아무것도 없으면 분석 범위 전체
    expect(pitchDomain([], null, null)).toEqual(range(70, 400))
  })

  it('세로축 여유는 낮은 목소리와 높은 목소리에 똑같이 (반음으로) 준다', () => {
    const lowVoice = sessionPitchDomain([point(now, { low: 100, high: 130 })], null, null)
    const highVoice = sessionPitchDomain([point(now, { low: 220, high: 286 })], null, null)
    const lowShare = semitones(100, 130) / semitones(lowVoice.lower, lowVoice.upper)
    const highShare = semitones(220, 286) / semitones(highVoice.lower, highVoice.upper)
    expect(Math.abs(lowShare - highShare)).toBeLessThan(1e-3)
  })

  it.each([
    [45, '45초'],
    [59.6, '1분'],
    [1500, '25분'],
    [3600, '1시간'],
    [11_400, '3시간 10분'],
    [11_430, '3시간 10분'],
  ])('모두 합친 시간 표시: %d초 → %s', (seconds, expected) => {
    expect(totalLabel(seconds)).toBe(expected)
  })
})

describe('연습 기록의 요청문 (AI에게 피드백 받기)', () => {
  const start = new Date(1_800_000_000_000)
  const readings = (from: number, count: number, frequency: number) =>
    Array.from({ length: count }, (_, i) => ({ time: from + i * 0.02, frequency }))

  /** 1번째 녹음은 170 Hz(그때 목표 140~160), 2번째는 190 Hz(목표 180~220), 정지한 때 목표 180~220 */
  function twoTakeSummary(): SessionSummary {
    const log = new PracticeSessionLog(start, 'en')
    for (const [index, frequency, target] of [
      [0, 170, range(140, 160)],
      [1, 190, range(180, 220)],
    ] as const) {
      log.beginTake()
      const take = readings(index * 100, 500, frequency)
      log.add(take)
      log.finishTake(take, 10, target, new Date(start.getTime() + (index + 1) * 40_000))
    }
    return log.finish(new Date(start.getTime() + 90_000), range(180, 220))!
  }

  it('녹음 한 줄 표시: 중앙·범위·목표 안 비율 (목표가 없으면 비율은 빼고)', () => {
    const withTarget = { round: 2, endedAt: start, pitch: new PitchSummary(60, 25, 182.4, 165, 201.2, range(160, 200), 0.72) }
    expect(takeNumbersLine(withTarget)).toBe('중앙 182 Hz · 165–201 Hz · 목표 안 72%')
    const noTarget = { round: 2, endedAt: start, pitch: new PitchSummary(60, 25, 182.4, 165, 201.2, null, null) }
    expect(takeNumbersLine(noTarget)).toBe('중앙 182 Hz · 165–201 Hz')
  })

  it('연습 전체와 녹음마다의 숫자를 넣고, 판정 없이 목표 범위를 기준으로 봐 달라고 쓴다', () => {
    const text = sessionFeedbackRequest(twoTakeSummary())
    for (const expected of [
      '[울림 · 보이스 트레이닝 연습 피드백 요청]',
      '녹음 2번',
      '말한 언어 영어',
      '연습 전체',
      '피치 중앙값: 180 Hz',
      '내 목표 범위: 180~220 Hz (목표 범위 안 비율 50%)',
      '- 1번째 녹음 (10초, 목소리 10.0초): 중앙 170 Hz, 범위 170~170 Hz, 목표 범위 안 0% (그때 목표 140~160 Hz)',
      '- 2번째 녹음 (10초, 목소리 10.0초): 중앙 190 Hz, 범위 190~190 Hz, 목표 범위 안 100%',
      '녹음마다 어떻게 달라졌는지',
      '녹음 파일은 보내지 않았어요',
      '짐작하지 말아 주세요',
      '성대에 무리가 가지 않는',
      '높이거나 낮추는 방향은 가정하지 말고',
      '보이스 트레이닝 앱 ‘울림’이 기기 안에서 직접 잰 값',
    ]) {
      expect(text, expected).toContain(expected)
    }
    // 2번째 녹음은 정지한 때와 목표가 같아 '그때 목표'를 다시 적지 않는다
    expect(text.split('그때 목표')).toHaveLength(2)
    for (const judgement of ['좋아', '나빠', '개선', '남성', '여성', '점수', 'VoicePractice']) {
      expect(text, judgement).not.toContain(judgement)
    }
  })

  it('녹음마다 기록이 없는 연습도 요청문을 만들 수 있고, 목표가 없으면 방향을 가정하지 말라고만 쓴다', () => {
    const old: SessionSummary = {
      startedAt: start,
      endedAt: new Date(start.getTime() + 300_000),
      takeCount: 3,
      language: 'ko',
      pitch: new PitchSummary(300, 80, 160, 140, 185, null, null),
      takes: [],
      f2Median: null,
    }
    const text = sessionFeedbackRequest(old)
    expect(text).toContain('녹음마다 기록이 없는 예전 연습')
    expect(text).toContain('내 목표 범위: 아직 정하지 않음')
    expect(text).toContain('높이거나 낮추는 방향은 가정하지 말아 주세요')
  })

  it('저장된 연습 기록에서 되돌린 요약으로 같은 요청문이 나온다 (녹음마다는 녹음 순서대로)', () => {
    const summary = twoTakeSummary()
    const record = sessionRecord(summary, 'id')
    const reversed = { ...record, takes: [...record.takes].reverse() }
    expect(sessionFeedbackRequest(sessionSummaryOf(reversed))).toBe(sessionFeedbackRequest(summary))
  })
})

describe('[기록] 그래프 자리', () => {
  const domain = { start: date(19, 0), end: date(26, 0) }
  const plot = { x: 36, y: 10, width: 280, height: 188 }

  it('가로 위치: 기간 첫날 0시가 왼쪽 끝, 내일 0시가 오른쪽 끝', () => {
    expect(timeX(date(19, 0), domain, plot)).toBe(36)
    expect(timeX(date(26, 0), domain, plot)).toBe(316)
    expect(timeX(date(22, 12), domain, plot)).toBeCloseTo(36 + 140, 9)
  })

  it('날짜 눈금은 많아야 5개, 첫날부터 고른 간격', () => {
    expect(dayTicks(domain)).toEqual([date(19, 0), date(21, 0), date(23, 0), date(25, 0)])
    const month = { start: date(26, 0, 9), end: date(26, 0) }
    expect(dayTicks(month)).toHaveLength(5)
    expect(dayTicks(month)[0]).toEqual(date(26, 0, 9))
  })

  it('분 눈금: 0부터 보기 좋은 간격으로, 가장 긴 날이 들어가게', () => {
    expect(minuteTicks(17)).toEqual([0, 10, 20])
    expect(minuteTicks(4)).toEqual([0, 2, 4])
    expect(minuteTicks(0.5)).toEqual([0, 1])
    expect(minuteTicks(95)).toEqual([0, 60, 120])
  })

  it('언어마다 점 모양이 다르다 (원·네모·세모·마름모)', () => {
    const shapes = (['ko', 'en', 'ja', 'other'] as const).map((language) => markerPath(language, 10, 10, 4))
    expect(new Set(shapes).size).toBe(4)
    expect(shapes[0]).toContain(' a ') // 원은 호(arc)로 그린다
  })
})

describe('기록 목록·개발용 가짜 기록', () => {
  it('알아볼 수 있는 기록만 화면 순서로: 연습은 오래된 것부터, 녹음·이력은 최근 것부터', () => {
    const records = sampleRecords(now, range(150, 190))
    const shuffled = { ...records, sessions: [...records.sessions].reverse().concat([{ id: 'x', unknown: true }]) }
    const readable = readableRecords(shuffled)
    expect(readable.sessions).toHaveLength(records.sessions.length)
    expect(Date.parse(readable.sessions[0].startedAt)).toBeLessThan(Date.parse(readable.sessions[1].startedAt))
    expect(Date.parse(readable.baselines[0].measuredAt)).toBeGreaterThan(Date.parse(readable.baselines[1].measuredAt))
    expect(readableRecords(EMPTY_RECORDS).sessions).toEqual([])
    // 같은 id가 두 번 있으면 처음 것만 (목록이 id로 줄을 구분하므로)
    const doubled = { ...records, sessions: [records.sessions[0], records.sessions[0]] }
    expect(readableRecords(doubled).sessions).toHaveLength(1)
  })

  it('가짜 기록: 40일 동안 사흘에 하루 쉬고, 닷새마다 아침 연습, 나흘마다 영어, 기준 이력 3개 (모두 기록 모양에 맞음)', () => {
    const records = sampleRecords(now, range(150, 190))
    // 0~40일 중 쉬는 날(나머지 1) 14일을 빼면 27일, 그중 닷새마다(0·5·…·40 중 쉬는 날이 아닌 날) 아침 연습이 더 있다
    const days = Array.from({ length: 41 }, (_, d) => d).filter((d) => d % 3 !== 1)
    expect(records.sessions).toHaveLength(days.length + days.filter((d) => d % 5 === 0).length)
    expect(records.sessions.every(isSessionRecord)).toBe(true)
    expect(records.baselineHistory).toHaveLength(3)
    expect(records.baselineHistory.every(isBaselineRecord)).toBe(true)
    const languages = new Set(readableRecords(records).sessions.map((s) => s.language))
    expect(languages).toEqual(new Set(['ko', 'en']))
  })
})
