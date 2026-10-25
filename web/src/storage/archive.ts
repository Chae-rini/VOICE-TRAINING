import type { Range } from '../dsp/range'
import type { VoiceBaseline } from '../model/practice'
import type { VoiceSettings } from '../model/voiceSettings'
import { VowelMaps } from '../model/vowelMap'

/**
 * 내 기록 폴더의 파일 모양 (W6). 사람이 열어 봐도 읽을 수 있게 들여 쓴 JSON으로 저장한다.
 * - `울림-설정.json`: 목표 범위, 내 기준 목소리, 내 모음 지도
 * - `울림-기록.json`: 연습 기록, 남긴 녹음 정보, 기준·모음 재기 이력 (항목 모양은 `model/records.ts`).
 *   모르는 모양의 항목(더 새 앱이 더한 것 등)도 읽은 그대로 다시 쓴다 (화면에는 쓰지 않는다)
 * - `녹음/Ullim-….wav`: 남긴 녹음의 소리
 * 읽지 못한 파일은 절대 덮어쓰지 않는다 (내 기록을 잃지 않게).
 */

export const SETTINGS_FILE = '울림-설정.json'
export const RECORDS_FILE = '울림-기록.json'
export const RECORDINGS_DIRECTORY = '녹음'
/** 이 앱이 읽고 쓰는 파일 모양의 판. 더 새 판의 파일은 읽기만 하고 고쳐 쓰지 않는다 */
export const FORMAT_VERSION = 1

/** 기록 파일의 네 목록. 항목은 파일에서 읽은 그대로 둔다 (모양 확인은 `model/records.ts`의 `is…Record`) */
export interface RecordsData {
  readonly sessions: readonly unknown[]
  readonly recordings: readonly unknown[]
  readonly baselineHistory: readonly unknown[]
  readonly vowelHistory: readonly unknown[]
}

export type RecordList = keyof RecordsData

export const EMPTY_RECORDS: RecordsData = { sessions: [], recordings: [], baselineHistory: [], vowelHistory: [] }

const RECORD_LISTS: readonly RecordList[] = ['sessions', 'recordings', 'baselineHistory', 'vowelHistory']

/** 기록의 id (없으면 null) */
export function recordIdOf(item: unknown): string | null {
  const id = (item as { id?: unknown } | null)?.id
  return typeof id === 'string' ? id : null
}

/** 목록 하나에 기록을 더한다 */
export function withRecord(records: RecordsData, list: RecordList, item: unknown): RecordsData {
  return { ...records, [list]: [...records[list], item] }
}

/**
 * 두 곳의 기록을 합친다: `base`는 그대로 두고, `extra`에서 `base`에 없는 id의 항목만 뒤에 더한다
 * (기록 폴더를 고르기 전·다시 연결하기 전에 화면에 쌓인 기록을 폴더 기록에 넣을 때).
 */
export function mergeRecords(base: RecordsData, extra: RecordsData): RecordsData {
  const merged: Record<RecordList, readonly unknown[]> = { ...base }
  for (const list of RECORD_LISTS) {
    const ids = new Set(base[list].map(recordIdOf).filter((id) => id !== null))
    const added = extra[list].filter((item) => {
      const id = recordIdOf(item)
      return id !== null && !ids.has(id)
    })
    if (added.length > 0) merged[list] = [...base[list], ...added]
  }
  return merged
}

/** 기록 수 (합쳤을 때 늘었는지 보기용) */
export function recordCount(records: RecordsData): number {
  return RECORD_LISTS.reduce((sum, list) => sum + records[list].length, 0)
}

/** 남긴 녹음의 파일 이름: Ullim-날짜-시각(초까지).wav. 같은 이름이 있으면 -2, -3을 붙인다 */
export function recordingFileName(date: Date, existing: ReadonlySet<string>): string {
  const two = (value: number) => String(value).padStart(2, '0')
  const day = `${date.getFullYear()}${two(date.getMonth() + 1)}${two(date.getDate())}`
  const base = `Ullim-${day}-${two(date.getHours())}${two(date.getMinutes())}${two(date.getSeconds())}`
  let name = `${base}.wav`
  for (let n = 2; existing.has(name); n++) name = `${base}-${n}.wav`
  return name
}

export type ParseFailure = 'broken' | 'notUllim' | 'newerVersion'
export type Parsed<T> = { readonly ok: true; readonly value: T } | { readonly ok: false; readonly reason: ParseFailure }

/** 읽지 못한 까닭을 화면 문구로 */
export function parseFailureMessage(file: string, reason: ParseFailure): string {
  switch (reason) {
    case 'broken':
      return `‘${file}’을 읽지 못했어요. 파일이 망가졌을 수 있어요. 덮어쓰지 않았으니 다른 폴더를 고르거나 파일을 확인해 주세요.`
    case 'notUllim':
      return `‘${file}’이 울림이 만든 파일이 아니에요. 덮어쓰지 않았으니 다른 폴더를 골라 주세요.`
    case 'newerVersion':
      return `‘${file}’은 더 새 판의 울림이 만든 파일이에요. 덮어쓰지 않았어요. 페이지를 새로 고쳐 최신 울림으로 열어 주세요.`
  }
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value)
}

function parseTarget(value: unknown): Range | null | undefined {
  if (value === null) return null
  const r = value as Range | undefined
  return r && isFiniteNumber(r.lower) && isFiniteNumber(r.upper) && r.lower < r.upper ? { lower: r.lower, upper: r.upper } : undefined
}

function parseBaseline(value: unknown): VoiceBaseline | null | undefined {
  if (value === null) return null
  const b = value as VoiceBaseline | undefined
  if (!b || !isFiniteNumber(b.median) || !isFiniteNumber(b.low) || !isFiniteNumber(b.high)) return undefined
  if (b.f2 !== null && !isFiniteNumber(b.f2)) return undefined
  return { median: b.median, low: b.low, high: b.high, f2: b.f2 }
}

/** JSON 글자 → 머리(app·kind·version)를 확인한 객체 */
function parseHeader(text: string, kind: 'settings' | 'records'): Parsed<Record<string, unknown>> {
  let json: unknown
  try {
    json = JSON.parse(text)
  } catch {
    return { ok: false, reason: 'broken' }
  }
  if (typeof json !== 'object' || json === null) return { ok: false, reason: 'broken' }
  const object = json as Record<string, unknown>
  if (object.app !== 'ullim' || object.kind !== kind) return { ok: false, reason: 'notUllim' }
  if (!Number.isInteger(object.version)) return { ok: false, reason: 'broken' }
  if ((object.version as number) > FORMAT_VERSION) return { ok: false, reason: 'newerVersion' }
  return { ok: true, value: object }
}

export function parseSettingsFile(text: string): Parsed<VoiceSettings> {
  const header = parseHeader(text, 'settings')
  if (!header.ok) return header
  const target = parseTarget(header.value.target ?? null)
  const baseline = parseBaseline(header.value.baseline ?? null)
  if (target === undefined || baseline === undefined) return { ok: false, reason: 'broken' }
  // 모음 지도는 모음마다 따로 읽는다 (망가진 모음 하나 때문에 전체를 버리지 않게)
  return { ok: true, value: { target, baseline, vowelMap: VowelMaps.decode(header.value.vowelMap) } }
}

export function encodeSettingsFile(settings: VoiceSettings, savedAt: Date): string {
  const file = {
    app: 'ullim',
    kind: 'settings',
    version: FORMAT_VERSION,
    savedAt: savedAt.toISOString(),
    target: settings.target,
    baseline: settings.baseline,
    vowelMap: settings.vowelMap,
  }
  return `${JSON.stringify(file, null, 2)}\n`
}

export function parseRecordsFile(text: string): Parsed<RecordsData> {
  const header = parseHeader(text, 'records')
  if (!header.ok) return header
  const list = (key: keyof RecordsData) => header.value[key] ?? []
  const lists = { sessions: list('sessions'), recordings: list('recordings'), baselineHistory: list('baselineHistory'), vowelHistory: list('vowelHistory') }
  if (!Object.values(lists).every(Array.isArray)) return { ok: false, reason: 'broken' }
  return { ok: true, value: lists as RecordsData }
}

export function encodeRecordsFile(records: RecordsData, savedAt: Date): string {
  const file = { app: 'ullim', kind: 'records', version: FORMAT_VERSION, savedAt: savedAt.toISOString(), ...records }
  return `${JSON.stringify(file, null, 2)}\n`
}
