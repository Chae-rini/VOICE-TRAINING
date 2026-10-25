import type { ScriptLength } from '../data/scripts'
import type { Range } from '../dsp/range'
import type { KoreanVowel } from '../text/korean'
import { PracticeDuration, type VoiceBaseline } from './practice'
import type { HistoryPeriod } from './history'
import type { PracticeLanguage } from './records'
import {
  browserStorage,
  clearLegacyVoiceSettings,
  loadLegacyVoiceSettings,
  loadSettings,
  saveValue,
  SettingKeys,
  type SentenceSource,
} from './settingsStorage'
import { withBaseline, type VoiceSettingField, type VoiceSettings } from './voiceSettings'
import { VowelMaps, type VowelEntry, type VowelMap } from './vowelMap'

/**
 * 화면이 함께 보는 설정.
 * - 화면 설정(들려줄 길이·문장 종류·대본 거르기·고른 모음·말하는 언어)은 바꾸면 이 브라우저에 바로 저장한다 (`settingsStorage.ts`)
 * - 내 기준 값(목표 범위·기준 목소리·모음 지도)은 바뀌었다고 알리기만 하고, 저장은 기록 폴더가 한다 (`storage/recordStore.svelte.ts`)
 */
class Settings {
  readonly #storage = browserStorage()
  #onVoiceChange: ((field: VoiceSettingField) => void) | null = null

  target: Range | null = $state(null)
  baseline: VoiceBaseline | null = $state(null)
  vowelMap: VowelMap = $state.raw({})
  baselinePromptShown = $state(false)
  practiceDuration = $state(PracticeDuration.defaultSeconds)
  sentenceSource: SentenceSource = $state('mine')
  scriptCategory = $state('')
  scriptLength: ScriptLength = $state('any')
  selectedVowel: KoreanVowel = $state('아')
  practiceLanguage: PracticeLanguage = $state('ko')
  historyPeriod: HistoryPeriod = $state('month')

  /** 저장소를 쓸 수 없어 화면 설정을 이번 실행 동안만 기억하는지 */
  readonly isTemporary = this.#storage === null
  /** W3~W5에서 이 브라우저에 저장한 내 기준 값을 아직 기록 폴더·기록 파일로 옮기지 않았는지 */
  hasLegacyValues = false

  constructor() {
    const stored = loadSettings(this.#storage)
    this.baselinePromptShown = stored.baselinePromptShown
    this.practiceDuration = stored.practiceDuration
    this.sentenceSource = stored.sentenceSource
    this.scriptCategory = stored.scriptCategory
    this.scriptLength = stored.scriptLength
    this.selectedVowel = stored.selectedVowel
    this.practiceLanguage = stored.practiceLanguage
    this.historyPeriod = stored.historyPeriod
    const legacy = loadLegacyVoiceSettings(this.#storage)
    if (legacy !== null) {
      this.#apply(legacy)
      this.hasLegacyValues = true
    }
  }

  // MARK: - 내 기준 값 (기록 폴더에 남는 값)

  get voiceSettings(): VoiceSettings {
    return { target: this.target, baseline: this.baseline, vowelMap: this.vowelMap }
  }

  /** 기록 폴더가 바뀐 값을 받아 저장한다 */
  observeVoiceChanges(listener: (field: VoiceSettingField) => void) {
    this.#onVoiceChange = listener
  }

  /** 기록 폴더·기록 파일에서 읽은 값으로 바꾼다 (다시 저장하지 않는다) */
  applyVoiceSettings(values: VoiceSettings) {
    this.#apply(values)
  }

  /** 기록 폴더·기록 파일로 옮긴 뒤 이 브라우저의 예전 값을 지운다 */
  forgetLegacyValues() {
    clearLegacyVoiceSettings(this.#storage)
    this.hasLegacyValues = false
  }

  #apply(values: VoiceSettings) {
    this.target = values.target
    this.baseline = values.baseline
    this.vowelMap = values.vowelMap
  }

  #changed(field: VoiceSettingField) {
    this.#onVoiceChange?.(field)
  }

  setTarget(target: Range) {
    this.target = target
    this.#changed('target')
  }

  /** 기준 목소리를 저장하고, `applyingTarget`이면 목표 범위도 기준 ±20 Hz로 바꾼다 */
  setBaseline(baseline: VoiceBaseline, applyingTarget: boolean) {
    this.#apply(withBaseline(this.voiceSettings, baseline, applyingTarget))
    this.#changed('baseline')
    if (applyingTarget) this.#changed('target')
  }

  /** 내 모음 지도에 모음 하나를 저장한다 (같은 모음은 새 값으로 바뀐다) */
  setVowelEntry(vowel: KoreanVowel, entry: VowelEntry) {
    this.vowelMap = VowelMaps.withEntry(this.vowelMap, vowel, entry)
    this.#changed('vowelMap')
  }

  // MARK: - 화면 설정 (이 브라우저에 남는 값)

  markBaselinePromptShown() {
    this.baselinePromptShown = true
    saveValue(this.#storage, SettingKeys.baselinePromptShown, true)
  }

  setPracticeDuration(seconds: number) {
    this.practiceDuration = PracticeDuration.normalized(seconds)
    saveValue(this.#storage, SettingKeys.practiceDuration, this.practiceDuration)
  }

  setSentenceSource(source: SentenceSource) {
    this.sentenceSource = source
    saveValue(this.#storage, SettingKeys.sentenceSource, source)
  }

  setScriptCategory(category: string) {
    this.scriptCategory = category
    saveValue(this.#storage, SettingKeys.scriptCategory, category)
  }

  setScriptLength(length: ScriptLength) {
    this.scriptLength = length
    saveValue(this.#storage, SettingKeys.scriptLength, length)
  }

  setSelectedVowel(vowel: KoreanVowel) {
    this.selectedVowel = vowel
    saveValue(this.#storage, SettingKeys.selectedVowel, vowel)
  }

  setPracticeLanguage(language: PracticeLanguage) {
    this.practiceLanguage = language
    saveValue(this.#storage, SettingKeys.practiceLanguage, language)
  }

  setHistoryPeriod(period: HistoryPeriod) {
    this.historyPeriod = period
    saveValue(this.#storage, SettingKeys.historyPeriod, period)
  }
}

export const settings = new Settings()
