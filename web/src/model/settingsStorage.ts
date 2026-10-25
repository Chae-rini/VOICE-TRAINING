import type { Range } from '../dsp/range'
import { SCRIPT_LENGTHS, ANY_CATEGORY, type ScriptLength } from '../data/scripts'
import { Baseline, PracticeDuration, type VoiceBaseline } from './practice'

/**
 * 설정 저장: 목표 범위, 내 기준 목소리, 들려줄 길이, 문장 종류, 대본 거르기.
 * 이 브라우저 안(localStorage)에만 둔다 (원칙 2). 키 이름은 iOS(UserDefaults)와 같게 맞추고 "ullim." 를 붙인다.
 * 저장소를 쓸 수 없는 브라우저(사생활 보호 모드 등)에서도 화면은 기본값으로 동작한다.
 */

export interface KeyValueStorage {
  getItem(key: string): string | null
  setItem(key: string, value: string): void
  removeItem(key: string): void
}

export const SENTENCE_SOURCES = [
  { id: 'mine', label: '내 문장' },
  { id: 'generated', label: '자동 생성' },
  { id: 'scripts', label: '대본' },
] as const
export type SentenceSource = (typeof SENTENCE_SOURCES)[number]['id']

export interface StoredSettings {
  /** [Hz] 목표 범위. 아직 없으면 null (기준 목소리를 잰 뒤에 생긴다 — 방향을 미리 정하지 않음) */
  readonly target: Range | null
  readonly baseline: VoiceBaseline | null
  /** 처음 열 때 "내 목소리 재기"를 한 번 띄웠는지 */
  readonly baselinePromptShown: boolean
  /** [s] 들려줄 길이 */
  readonly practiceDuration: number
  readonly sentenceSource: SentenceSource
  readonly scriptCategory: string
  readonly scriptLength: ScriptLength
}

const PREFIX = 'ullim.'
export const SettingKeys = {
  targetLower: 'targetLowerHz',
  targetUpper: 'targetUpperHz',
  baselineMedian: 'baselineMedianHz',
  baselineLow: 'baselineLowHz',
  baselineHigh: 'baselineHighHz',
  baselineF2: 'baselineF2Hz',
  baselinePromptShown: 'baselinePromptShown',
  practiceDuration: 'practiceDurationSeconds',
  sentenceSource: 'sentenceSource',
  scriptCategory: 'scriptCategory',
  scriptLength: 'scriptLength',
} as const

/** 이 브라우저의 저장소. 쓸 수 없으면 null */
export function browserStorage(): KeyValueStorage | null {
  try {
    const storage = globalThis.localStorage
    const probe = `${PREFIX}probe`
    storage.setItem(probe, '1')
    storage.removeItem(probe)
    return storage
  } catch {
    return null
  }
}

function read(storage: KeyValueStorage | null, key: string): string | null {
  try {
    return storage?.getItem(PREFIX + key) ?? null
  } catch {
    return null
  }
}

function write(storage: KeyValueStorage | null, key: string, value: string | number | boolean | null): void {
  try {
    if (value === null) storage?.removeItem(PREFIX + key)
    else storage?.setItem(PREFIX + key, String(value))
  } catch {
    // 저장소가 가득 찼거나 막혀 있으면 이번 실행 동안만 기억한다.
  }
}

function readNumber(storage: KeyValueStorage | null, key: string): number | null {
  const text = read(storage, key)
  if (text === null) return null
  const value = Number(text)
  return Number.isFinite(value) ? value : null
}

export function loadSettings(storage: KeyValueStorage | null): StoredSettings {
  const lower = readNumber(storage, SettingKeys.targetLower)
  const upper = readNumber(storage, SettingKeys.targetUpper)
  const median = readNumber(storage, SettingKeys.baselineMedian)
  const low = readNumber(storage, SettingKeys.baselineLow)
  const high = readNumber(storage, SettingKeys.baselineHigh)
  const source = read(storage, SettingKeys.sentenceSource)
  const length = read(storage, SettingKeys.scriptLength)
  const duration = readNumber(storage, SettingKeys.practiceDuration)
  return {
    target: lower !== null && upper !== null ? { lower: Math.min(lower, upper), upper: Math.max(lower, upper) } : null,
    baseline:
      median !== null && low !== null && high !== null
        ? { median, low, high, f2: readNumber(storage, SettingKeys.baselineF2) }
        : null,
    baselinePromptShown: read(storage, SettingKeys.baselinePromptShown) === 'true',
    practiceDuration: PracticeDuration.normalized(duration ?? PracticeDuration.defaultSeconds),
    sentenceSource: SENTENCE_SOURCES.some((s) => s.id === source) ? (source as SentenceSource) : 'mine',
    scriptCategory: read(storage, SettingKeys.scriptCategory) ?? ANY_CATEGORY,
    scriptLength: SCRIPT_LENGTHS.some((l) => l.id === length) ? (length as ScriptLength) : 'any',
  }
}

export function saveTarget(storage: KeyValueStorage | null, target: Range | null): void {
  write(storage, SettingKeys.targetLower, target?.lower ?? null)
  write(storage, SettingKeys.targetUpper, target?.upper ?? null)
}

/**
 * 기준 목소리를 저장한다. `applyingTarget`이면 목표 범위를 기준 ±20 Hz로 바꾸고 그 범위를 돌려준다.
 * F2를 못 잰 기준이면 예전 기준의 F2도 지운다 (다른 날 잰 피치와 F2가 섞이지 않게).
 */
export function saveBaseline(storage: KeyValueStorage | null, baseline: VoiceBaseline, applyingTarget: boolean): Range | null {
  write(storage, SettingKeys.baselineMedian, baseline.median)
  write(storage, SettingKeys.baselineLow, baseline.low)
  write(storage, SettingKeys.baselineHigh, baseline.high)
  write(storage, SettingKeys.baselineF2, baseline.f2)
  if (!applyingTarget) return null
  const target = Baseline.initialTarget(baseline)
  saveTarget(storage, target)
  return target
}

export function saveValue(storage: KeyValueStorage | null, key: (typeof SettingKeys)[keyof typeof SettingKeys], value: string | number | boolean): void {
  write(storage, key, value)
}
