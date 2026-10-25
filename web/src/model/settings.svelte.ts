import type { ScriptLength } from '../data/scripts'
import type { Range } from '../dsp/range'
import { PracticeDuration, type VoiceBaseline } from './practice'
import {
  browserStorage,
  loadSettings,
  saveBaseline,
  saveTarget,
  saveValue,
  SettingKeys,
  type SentenceSource,
} from './settingsStorage'

/** 화면이 함께 보는 설정. 값을 바꾸면 이 브라우저에 바로 저장한다 (규칙은 `settingsStorage.ts`). */
class Settings {
  readonly #storage = browserStorage()

  target: Range | null = $state(null)
  baseline: VoiceBaseline | null = $state(null)
  baselinePromptShown = $state(false)
  practiceDuration = $state(PracticeDuration.defaultSeconds)
  sentenceSource: SentenceSource = $state('mine')
  scriptCategory = $state('')
  scriptLength: ScriptLength = $state('any')

  /** 저장소를 쓸 수 없어 이번 실행 동안만 기억하는지 */
  readonly isTemporary = this.#storage === null

  constructor() {
    const stored = loadSettings(this.#storage)
    this.target = stored.target
    this.baseline = stored.baseline
    this.baselinePromptShown = stored.baselinePromptShown
    this.practiceDuration = stored.practiceDuration
    this.sentenceSource = stored.sentenceSource
    this.scriptCategory = stored.scriptCategory
    this.scriptLength = stored.scriptLength
  }

  setTarget(target: Range) {
    this.target = target
    saveTarget(this.#storage, target)
  }

  /** 기준 목소리를 저장하고, `applyingTarget`이면 목표 범위도 기준 ±20 Hz로 바꾼다 */
  setBaseline(baseline: VoiceBaseline, applyingTarget: boolean) {
    this.baseline = baseline
    const target = saveBaseline(this.#storage, baseline, applyingTarget)
    if (target !== null) this.target = target
  }

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
}

export const settings = new Settings()
