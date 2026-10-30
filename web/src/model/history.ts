import { FREQUENCY_RANGE } from '../dsp/pitchDetector'
import { offsetBySemitones, semitones } from '../dsp/pitchScale'
import type { Range } from '../dsp/range'
import { VowelSpace } from '../dsp/vowelSpace'
import type { PracticeLanguage, SessionRecord } from './records'

/**
 * [기록] 화면의 계산 규칙 (iOS `Models/PracticeHistory.swift`). 점수·향상률·연속 기록(스트릭)은 만들지 않고, 있는 숫자를 모으기만 한다.
 * 날짜는 이 기기의 시간대로 센다 (하루 = 그날 0시부터).
 */

export const HISTORY_PERIODS = [
  { id: 'week', label: '7일' },
  { id: 'month', label: '30일' },
  { id: 'all', label: '전체' },
] as const
export type HistoryPeriod = (typeof HISTORY_PERIODS)[number]['id']

export function isHistoryPeriod(value: unknown): value is HistoryPeriod {
  return HISTORY_PERIODS.some((period) => period.id === value)
}

/** 그날 0시 */
export function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

/** `days`일 뒤(앞이면 음수)의 0시 */
export function addDays(day: Date, days: number): Date {
  return new Date(day.getFullYear(), day.getMonth(), day.getDate() + days)
}

/** 이 기간의 첫날 0시. 오늘도 하루로 센다 (7일 = 오늘과 그 앞 6일). 전체면 null */
export function periodStart(period: HistoryPeriod, now: Date): Date | null {
  const today = startOfDay(now)
  switch (period) {
    case 'week':
      return addDays(today, -6)
    case 'month':
      return addDays(today, -29)
    case 'all':
      return null
  }
}

export function periodContains(period: HistoryPeriod, date: Date, now: Date): boolean {
  const start = periodStart(period, now)
  return start === null || date >= start
}

/** 그래프에 찍을 연습 한 번 (연습 기록에서 필요한 값만 꺼낸 것) */
export interface SessionPoint {
  readonly startedAt: Date
  /** [s] 시작~정지 시간 */
  readonly practiceSeconds: number
  /** [Hz] 중앙값, 아래 10%, 위 10% */
  readonly median: number
  readonly low: number
  readonly high: number
  readonly language: PracticeLanguage
  /** [Hz] 연습 전체의 F2 중앙값 (공명 밝기). 2026-10-25 전의 연습과 포먼트를 충분히 못 잡은 연습은 null */
  readonly f2: number | null
}

export function sessionPoint(record: SessionRecord): SessionPoint {
  return {
    startedAt: new Date(record.startedAt),
    practiceSeconds: record.pitch.duration,
    median: record.pitch.median,
    low: record.pitch.p10,
    high: record.pitch.p90,
    language: record.language,
    f2: record.f2Median,
  }
}

/** 하루 동안 연습한 시간 (막대그래프용) */
export interface DailyPractice {
  /** 그날 0시 */
  readonly day: Date
  readonly minutes: number
}

export interface HistoryTotals {
  readonly sessionCount: number
  /** 연습한 날 수 (연속 여부는 따지지 않음) */
  readonly dayCount: number
  /** [s] */
  readonly practiceSeconds: number
}

/** 기간과 언어(null이면 모두)에 맞는 연습만 남긴다 */
export function filterPoints(
  points: readonly SessionPoint[],
  period: HistoryPeriod,
  language: PracticeLanguage | null,
  now: Date,
): SessionPoint[] {
  return points.filter((point) => periodContains(period, point.startedAt, now) && (language === null || point.language === language))
}

/** 날마다 연습한 시간을 더한다. 연습을 시작한 날로 센다 (자정을 넘긴 연습도 시작한 날) */
export function dailyPractice(points: readonly SessionPoint[]): DailyPractice[] {
  const byDay = new Map<number, number>()
  for (const point of points) {
    const day = startOfDay(point.startedAt).getTime()
    byDay.set(day, (byDay.get(day) ?? 0) + point.practiceSeconds)
  }
  return [...byDay]
    .sort(([a], [b]) => a - b)
    .map(([day, seconds]) => ({ day: new Date(day), minutes: seconds / 60 }))
}

export function historyTotals(points: readonly SessionPoint[]): HistoryTotals {
  return {
    sessionCount: points.length,
    dayCount: new Set(points.map((point) => startOfDay(point.startedAt).getTime())).size,
    practiceSeconds: points.reduce((sum, point) => sum + point.practiceSeconds, 0),
  }
}

/** 그래프 가로축: 기간 첫날 0시 ~ 내일 0시. 전체면 가장 이른 연습한 날부터 (연습이 없으면 최근 7일) */
export function dateDomain(points: readonly SessionPoint[], period: HistoryPeriod, now: Date): { start: Date; end: Date } {
  const today = startOfDay(now)
  const earliest = points.reduce<Date | null>((min, point) => (min === null || point.startedAt < min ? point.startedAt : min), null)
  const start = periodStart(period, now) ?? (earliest === null ? null : startOfDay(earliest)) ?? periodStart('week', now)!
  return { start, end: addDays(today, 1) }
}

/** [반음] 이보다 좁게는 보여 주지 않는다 (작은 차이가 크게 부풀어 보이지 않게) */
export const MINIMUM_PITCH_SPAN_SEMITONES = 6
/** [반음] 위아래 여유 */
export const PITCH_PADDING_SEMITONES = 1.5

/**
 * 그래프 세로축 [Hz]: 높이들(연습의 아래 10%·위 10% 등), 목표 범위, 기준이 모두 들어가게 잡고 분석 범위(70~400 Hz) 안으로 자른다.
 * 그래프가 반음 눈금이라 여유와 최소 폭도 반음으로 잡는다 (높은 쪽·낮은 쪽이 같은 여유를 갖게). 두 녹음 비교 그래프도 쓴다.
 */
export function pitchDomain(values: readonly number[], target: Range | null, baseline: number | null): Range {
  const all = [...values, ...(target === null ? [] : [target.lower, target.upper]), ...(baseline === null ? [] : [baseline])]
  return semitoneDomain(all, FREQUENCY_RANGE)
}

/**
 * 공명 밝기 그래프의 세로축 [Hz] (iOS `PracticeHistory.resonanceDomain`): 연습마다 F2 중앙값과 기준 F2가 모두 들어가게,
 * 높이 축과 같은 반음 여유·최소 폭으로 잡고 모음 지도의 F2 범위(600~3000 Hz) 안으로 자른다. F2가 없는 연습은 세지 않는다.
 */
export function resonanceDomain(points: readonly SessionPoint[], baseline: number | null): Range {
  const values = points.flatMap((point) => (point.f2 === null ? [] : [point.f2]))
  return semitoneDomain(baseline === null ? values : [...values, baseline], VowelSpace.f2Range)
}

/**
 * 값 [Hz]들이 모두 들어가는 반음(로그) 눈금 축. 위아래 반음 `PITCH_PADDING_SEMITONES`개 여유, 최소 반음 `MINIMUM_PITCH_SPAN_SEMITONES`개 폭,
 * `axis` 밖으로 나가면 안쪽으로 민다. 값이 없으면 `axis` 전체.
 */
function semitoneDomain(all: readonly number[], axis: Range): Range {
  if (all.length === 0) return axis

  let lower = offsetBySemitones(Math.min(...all), -PITCH_PADDING_SEMITONES)
  let upper = offsetBySemitones(Math.max(...all), PITCH_PADDING_SEMITONES)
  if (semitones(lower, upper) < MINIMUM_PITCH_SPAN_SEMITONES) {
    // 반음 눈금의 가운데 = 두 끝의 기하평균
    const center = Math.sqrt(lower * upper)
    lower = offsetBySemitones(center, -MINIMUM_PITCH_SPAN_SEMITONES / 2)
    upper = offsetBySemitones(center, MINIMUM_PITCH_SPAN_SEMITONES / 2)
  }
  // 범위 밖으로 나가면 안쪽으로 밀어 넣는다 (가능한 한 반음 폭은 유지)
  if (lower < axis.lower) {
    const shift = semitones(lower, axis.lower)
    upper = Math.min(offsetBySemitones(upper, shift), axis.upper)
    lower = axis.lower
  }
  if (upper > axis.upper) {
    const shift = semitones(upper, axis.upper) // 음수
    lower = Math.max(offsetBySemitones(lower, shift), axis.lower)
    upper = axis.upper
  }
  return { lower, upper }
}

/** 연습들의 세로축 */
export function sessionPitchDomain(points: readonly SessionPoint[], target: Range | null, baseline: number | null): Range {
  return pitchDomain(
    points.flatMap((point) => [point.low, point.high]),
    target,
    baseline,
  )
}

/** 예: 45초 → "45초", 1500초 → "25분", 11400초 → "3시간 10분". 1분이 넘으면 초는 버린다 */
export function totalLabel(seconds: number): string {
  const total = Math.round(seconds)
  if (total < 60) return `${total}초`
  const hours = Math.floor(total / 3600)
  const minutes = Math.floor((total % 3600) / 60)
  if (hours === 0) return `${minutes}분`
  return minutes === 0 ? `${hours}시간` : `${hours}시간 ${minutes}분`
}
