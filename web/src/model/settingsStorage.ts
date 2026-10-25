import { SCRIPT_LENGTHS, ANY_CATEGORY, type ScriptLength } from '../data/scripts'
import { KOREAN_VOWELS, type KoreanVowel } from '../text/korean'
import { isHistoryPeriod, type HistoryPeriod } from './history'
import { PracticeDuration } from './practice'
import { isPracticeLanguage, type PracticeLanguage } from './records'
import type { VoiceSettings } from './voiceSettings'
import { VowelMaps } from './vowelMap'

/**
 * 화면 설정 저장: 들려줄 길이, 문장 종류, 대본 거르기, 고른 모음, 말하는 언어, [기록]에서 보는 기간, 처음 안내를 띄웠는지.
 * 이 브라우저 안(localStorage)에 둔다. 키 이름은 iOS(UserDefaults)와 같게 맞추고 "ullim." 를 붙인다.
 * 저장소를 쓸 수 없는 브라우저(사생활 보호 모드 등)에서도 화면은 기본값으로 동작한다.
 *
 * 목표 범위·내 기준 목소리·내 모음 지도는 W6부터 내 기록 폴더에 둔다 (`storage/`). W3~W5에서 이 브라우저에 저장한 값은
 * 한 번 읽어 와서 기록 폴더(또는 기록 파일)에 옮긴 뒤 지운다 (`loadLegacyVoiceSettings`·`clearLegacyVoiceSettings`).
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
  /** 처음 열 때 "내 목소리 재기"를 한 번 띄웠는지 */
  readonly baselinePromptShown: boolean
  /** [s] 들려줄 길이 */
  readonly practiceDuration: number
  readonly sentenceSource: SentenceSource
  readonly scriptCategory: string
  readonly scriptLength: ScriptLength
  /** [모음] 화면에서 고른 모음 */
  readonly selectedVowel: KoreanVowel
  /** 연습할 때 말하는 언어 (기록에 함께 남는다) */
  readonly practiceLanguage: PracticeLanguage
  /** [기록]에서 보는 기간 */
  readonly historyPeriod: HistoryPeriod
}

const PREFIX = 'ullim.'
export const SettingKeys = {
  baselinePromptShown: 'baselinePromptShown',
  practiceDuration: 'practiceDurationSeconds',
  sentenceSource: 'sentenceSource',
  scriptCategory: 'scriptCategory',
  scriptLength: 'scriptLength',
  selectedVowel: 'selectedVowel',
  practiceLanguage: 'practiceLanguage',
  historyPeriod: 'historyPeriod',
} as const

/** W3~W5에서 이 브라우저에 두었던 내 기준 값의 키 (옮긴 뒤 지운다) */
export const LegacyVoiceKeys = {
  targetLower: 'targetLowerHz',
  targetUpper: 'targetUpperHz',
  baselineMedian: 'baselineMedianHz',
  baselineLow: 'baselineLowHz',
  baselineHigh: 'baselineHighHz',
  baselineF2: 'baselineF2Hz',
  vowelMap: 'vowelMap',
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
  const source = read(storage, SettingKeys.sentenceSource)
  const length = read(storage, SettingKeys.scriptLength)
  const duration = readNumber(storage, SettingKeys.practiceDuration)
  const vowel = read(storage, SettingKeys.selectedVowel)
  const language = read(storage, SettingKeys.practiceLanguage)
  const period = read(storage, SettingKeys.historyPeriod)
  return {
    baselinePromptShown: read(storage, SettingKeys.baselinePromptShown) === 'true',
    practiceDuration: PracticeDuration.normalized(duration ?? PracticeDuration.defaultSeconds),
    sentenceSource: SENTENCE_SOURCES.some((s) => s.id === source) ? (source as SentenceSource) : 'mine',
    scriptCategory: read(storage, SettingKeys.scriptCategory) ?? ANY_CATEGORY,
    scriptLength: SCRIPT_LENGTHS.some((l) => l.id === length) ? (length as ScriptLength) : 'any',
    selectedVowel: KOREAN_VOWELS.find((v) => v === vowel) ?? '아',
    practiceLanguage: isPracticeLanguage(language) ? language : 'ko',
    historyPeriod: isHistoryPeriod(period) ? period : 'month',
  }
}

/** W3~W5에서 이 브라우저에 저장한 내 기준 값. 하나도 없으면 null */
export function loadLegacyVoiceSettings(storage: KeyValueStorage | null): VoiceSettings | null {
  const keys = LegacyVoiceKeys
  const lower = readNumber(storage, keys.targetLower)
  const upper = readNumber(storage, keys.targetUpper)
  const median = readNumber(storage, keys.baselineMedian)
  const low = readNumber(storage, keys.baselineLow)
  const high = readNumber(storage, keys.baselineHigh)
  const legacy: VoiceSettings = {
    target: lower !== null && upper !== null ? { lower: Math.min(lower, upper), upper: Math.max(lower, upper) } : null,
    baseline: median !== null && low !== null && high !== null ? { median, low, high, f2: readNumber(storage, keys.baselineF2) } : null,
    vowelMap: VowelMaps.parse(read(storage, keys.vowelMap)),
  }
  const isEmpty = legacy.target === null && legacy.baseline === null && VowelMaps.measuredCount(legacy.vowelMap) === 0
  return isEmpty ? null : legacy
}

/** 기록 폴더(또는 기록 파일)로 옮긴 뒤 이 브라우저의 예전 값을 지운다 */
export function clearLegacyVoiceSettings(storage: KeyValueStorage | null): void {
  for (const key of Object.values(LegacyVoiceKeys)) write(storage, key, null)
}

export function saveValue(storage: KeyValueStorage | null, key: (typeof SettingKeys)[keyof typeof SettingKeys], value: string | number | boolean): void {
  write(storage, key, value)
}
