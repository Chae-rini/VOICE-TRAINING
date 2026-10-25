import { PitchSummary } from '../dsp/pitchSummary'
import type { Range } from '../dsp/range'
import { formatShortDateTime } from '../text/dates'
import { KOREAN_VOWELS, type KoreanVowel } from '../text/korean'
import type { VoiceBaseline } from './practice'
import { VowelMaps, type VowelEntry } from './vowelMap'

/**
 * `울림-기록.json`에 남는 기록의 모양 (iOS `Models/PracticeRecord.swift`의 SwiftData 기록과 같은 내용).
 * 소리는 남긴 녹음만 `녹음/` 폴더에 WAV로 두고, 나머지는 숫자만이다. 날짜는 ISO 8601 글자로 쓴다.
 * 모든 기록에는 `id`가 있어, 두 곳의 기록을 합칠 때(폴더를 고르기 전에 쌓인 기록 등) 같은 것을 두 번 넣지 않는다.
 */

/** 연습할 때 말한 언어. 기록에 함께 남겨 나중에 언어마다 높이를 비교한다. 화면 글자는 한국어 그대로 (원칙 5) */
export const PRACTICE_LANGUAGES = [
  { id: 'ko', label: '한국어' },
  { id: 'en', label: '영어' },
  { id: 'ja', label: '일본어' },
  { id: 'other', label: '기타' },
] as const
export type PracticeLanguage = (typeof PRACTICE_LANGUAGES)[number]['id']

export function isPracticeLanguage(value: unknown): value is PracticeLanguage {
  return PRACTICE_LANGUAGES.some((language) => language.id === value)
}

export function languageLabel(language: PracticeLanguage): string {
  return PRACTICE_LANGUAGES.find((l) => l.id === language)?.label ?? '기타'
}

/** 저장하는 피치 요약 숫자 (`PitchSummary`와 같은 이름) */
export interface PitchNumbers {
  /** [s] 녹음 길이 (연습 기록은 시작~정지 시간) */
  readonly duration: number
  /** [s] 목소리가 잡힌 시간 */
  readonly voicedSeconds: number
  /** [Hz] 중앙값, 아래 10%, 위 10% */
  readonly median: number
  readonly p10: number
  readonly p90: number
  /** [Hz] 그때의 목표 범위. 정하지 않았으면 null */
  readonly target: Range | null
  /** 0~1. 목표 범위 안에 있던 비율 */
  readonly inTargetFraction: number | null
}

export function pitchNumbers(summary: PitchSummary): PitchNumbers {
  const { duration, voicedSeconds, median, p10, p90, target, inTargetFraction } = summary
  return { duration, voicedSeconds, median, p10, p90, target, inTargetFraction }
}

export function pitchSummaryOf(n: PitchNumbers): PitchSummary {
  return new PitchSummary(n.duration, n.voicedSeconds, n.median, n.p10, n.p90, n.target, n.inTargetFraction)
}

/** 연습 중 녹음 한 번의 요약 (‘지금 들어보기’를 누르거나 녹음 중에 정지할 때마다 하나) */
export interface TakeRecord {
  /** 연습 안에서 몇 번째 녹음인지 (1부터) */
  readonly round: number
  readonly endedAt: string
  readonly pitch: PitchNumbers
}

/** 연습 한 번(‘반복 루프 재생’부터 정지까지)의 요약. 정지하면 자동으로 남는다 */
export interface SessionRecord {
  readonly id: string
  readonly startedAt: string
  readonly endedAt: string
  /** 녹음한 횟수 */
  readonly takeCount: number
  readonly language: PracticeLanguage
  readonly pitch: PitchNumbers
  /** [Hz] 연습 전체의 F2 중앙값 (공명 밝기). 포먼트가 충분히 잡히지 않았으면 null */
  readonly f2Median: number | null
  /** 녹음마다의 요약 (목소리가 잡힌 녹음만, 녹음 순서대로) */
  readonly takes: readonly TakeRecord[]
}

/** ‘기록에 남기기’를 누른 녹음. 소리는 `녹음/<fileName>` */
export interface RecordingRecord {
  readonly id: string
  readonly recordedAt: string
  /** 불러온 파일의 이름. 앱에서 녹음한 것이면 빈 글자 */
  readonly title: string
  readonly memo: string
  /** 녹음 폴더 안의 파일 이름 */
  readonly fileName: string
  readonly language: PracticeLanguage
  readonly pitch: PitchNumbers
  /** [Hz] 녹음 전체의 F2 중앙값. 포먼트를 못 쟀으면 null */
  readonly f2Median: number | null
}

/** ‘내 목소리 재기’를 저장할 때마다 하나 */
export interface BaselineRecord extends VoiceBaseline {
  readonly id: string
  readonly measuredAt: string
}

/** 내 모음 지도에서 모음 하나를 잴 때마다 하나 (지도에는 모음마다 마지막 값만 보인다) */
export interface VowelRecord extends VowelEntry {
  readonly id: string
  readonly vowel: KoreanVowel
}

/** 기록 파일의 목록마다 들어가는 기록 */
export interface RecordItems {
  readonly sessions: SessionRecord
  readonly recordings: RecordingRecord
  readonly baselineHistory: BaselineRecord
  readonly vowelHistory: VowelRecord
}

/** 남긴 녹음의 화면 이름: 불러온 파일이면 파일 이름, 앱에서 녹음했으면 "10월 25일 오후 8:12 녹음" */
export function recordingDisplayTitle(record: RecordingRecord): string {
  return record.title === '' ? `${formatShortDateTime(new Date(record.recordedAt))} 녹음` : record.title
}

export function newRecordId(): string {
  return crypto.randomUUID()
}

// MARK: - 읽을 때 확인 (모르는 모양의 항목은 화면에 쓰지 않지만, 파일에서 지우지도 않는다)

function isNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value)
}

function isNumberOrNull(value: unknown): boolean {
  return value === null || isNumber(value)
}

function isDate(value: unknown): value is string {
  return typeof value === 'string' && !Number.isNaN(Date.parse(value))
}

function isRange(value: unknown): value is Range {
  const r = value as Range | null
  return typeof r === 'object' && r !== null && isNumber(r.lower) && isNumber(r.upper)
}

function isPitchNumbers(value: unknown): value is PitchNumbers {
  const p = value as PitchNumbers | null
  return (
    typeof p === 'object' &&
    p !== null &&
    [p.duration, p.voicedSeconds, p.median, p.p10, p.p90].every(isNumber) &&
    (p.target === null || isRange(p.target)) &&
    isNumberOrNull(p.inTargetFraction)
  )
}

function hasId(value: unknown): value is { id: string } {
  return typeof value === 'object' && value !== null && typeof (value as { id: unknown }).id === 'string'
}

export function isSessionRecord(value: unknown): value is SessionRecord {
  if (!hasId(value)) return false
  const s = value as SessionRecord
  return (
    isDate(s.startedAt) &&
    isDate(s.endedAt) &&
    isNumber(s.takeCount) &&
    isPracticeLanguage(s.language) &&
    isPitchNumbers(s.pitch) &&
    isNumberOrNull(s.f2Median) &&
    Array.isArray(s.takes) &&
    s.takes.every((t) => isNumber(t?.round) && isDate(t?.endedAt) && isPitchNumbers(t?.pitch))
  )
}

export function isRecordingRecord(value: unknown): value is RecordingRecord {
  if (!hasId(value)) return false
  const r = value as RecordingRecord
  return (
    isDate(r.recordedAt) &&
    typeof r.title === 'string' &&
    typeof r.memo === 'string' &&
    typeof r.fileName === 'string' &&
    isPracticeLanguage(r.language) &&
    isPitchNumbers(r.pitch) &&
    isNumberOrNull(r.f2Median)
  )
}

export function isBaselineRecord(value: unknown): value is BaselineRecord {
  if (!hasId(value)) return false
  const b = value as BaselineRecord
  return isDate(b.measuredAt) && [b.median, b.low, b.high].every(isNumber) && isNumberOrNull(b.f2)
}

export function isVowelRecord(value: unknown): value is VowelRecord {
  if (!hasId(value)) return false
  const v = value as VowelRecord
  return KOREAN_VOWELS.includes(v.vowel) && VowelMaps.decode({ [v.vowel]: v })[v.vowel] !== undefined
}

// MARK: - 화면에서 쓰기

/** 기록 파일의 목록에서 알아볼 수 있는 기록만, 화면에 쓰는 순서로 */
export interface ReadableRecords {
  /** 오래된 것부터 (그래프 순서) */
  readonly sessions: readonly SessionRecord[]
  /** 최근 것부터 (목록 순서) */
  readonly recordings: readonly RecordingRecord[]
  readonly baselines: readonly BaselineRecord[]
  readonly vowels: readonly VowelRecord[]
}

function byTime<T>(time: (item: T) => string, newestFirst: boolean): (a: T, b: T) => number {
  return (a, b) => (Date.parse(time(a)) - Date.parse(time(b))) * (newestFirst ? -1 : 1)
}

/** 같은 id가 두 번 들어 있으면(손으로 고친 기록 파일 등) 처음 것만 쓴다 (화면 목록이 id로 줄을 구분하므로) */
function uniqueIds<T extends { readonly id: string }>(items: T[]): T[] {
  const seen = new Set<string>()
  return items.filter((item) => {
    if (seen.has(item.id)) return false
    seen.add(item.id)
    return true
  })
}

export function readableRecords(data: {
  readonly sessions: readonly unknown[]
  readonly recordings: readonly unknown[]
  readonly baselineHistory: readonly unknown[]
  readonly vowelHistory: readonly unknown[]
}): ReadableRecords {
  return {
    sessions: uniqueIds(data.sessions.filter(isSessionRecord)).sort(byTime((s) => s.startedAt, false)),
    recordings: uniqueIds(data.recordings.filter(isRecordingRecord)).sort(byTime((r) => r.recordedAt, true)),
    baselines: uniqueIds(data.baselineHistory.filter(isBaselineRecord)).sort(byTime((b) => b.measuredAt, true)),
    vowels: uniqueIds(data.vowelHistory.filter(isVowelRecord)).sort(byTime((v) => v.measuredAt, true)),
  }
}
