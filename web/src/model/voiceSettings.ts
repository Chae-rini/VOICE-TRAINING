import type { Range } from '../dsp/range'
import { KOREAN_VOWELS, type KoreanVowel } from '../text/korean'
import { Baseline, type VoiceBaseline } from './practice'
import type { VowelEntry, VowelMap } from './vowelMap'

/**
 * 내 기준 값: 목표 범위, 내 기준 목소리, 내 모음 지도.
 * 브라우저가 아니라 내 기록 폴더의 `울림-설정.json`(폴더를 고를 수 없는 브라우저는 기록 파일)에 남는다 (W6, 사용자 결정).
 */
export interface VoiceSettings {
  /** [Hz] 목표 범위. 아직 없으면 null (기준 목소리를 잰 뒤에 생긴다 — 방향을 미리 정하지 않음) */
  readonly target: Range | null
  readonly baseline: VoiceBaseline | null
  /** 모음마다 마지막에 잰 값 */
  readonly vowelMap: VowelMap
}

export type VoiceSettingField = keyof VoiceSettings

export const EMPTY_VOICE_SETTINGS: VoiceSettings = { target: null, baseline: null, vowelMap: {} }

/**
 * 기준 목소리를 바꾼다. `applyingTarget`이면 목표 범위를 기준 ±20 Hz로 바꾼다.
 * F2를 못 잰 기준이면 F2도 비운다 (다른 날 잰 피치와 F2가 섞이지 않게).
 */
export function withBaseline(current: VoiceSettings, baseline: VoiceBaseline, applyingTarget: boolean): VoiceSettings {
  return { ...current, baseline, target: applyingTarget ? Baseline.initialTarget(baseline) : current.target }
}

/** 모음마다 나중에 잰 값을 남긴다 */
export function mergeVowelMaps(a: VowelMap, b: VowelMap): VowelMap {
  const merged: Partial<Record<KoreanVowel, VowelEntry>> = {}
  for (const vowel of KOREAN_VOWELS) {
    const x = a[vowel]
    const y = b[vowel]
    const newer = x === undefined ? y : y === undefined ? x : Date.parse(y.measuredAt) > Date.parse(x.measuredAt) ? y : x
    if (newer !== undefined) merged[vowel] = newer
  }
  return merged
}

/**
 * 기록 폴더를 열 때 폴더의 값과 지금 화면의 값을 합친다.
 * - 이번에 화면에서 바꾼 값(`changed`)은 화면 값을 남긴다 (폴더에 다시 연결하기 전에 바꾼 것을 잃지 않게)
 * - 그 밖에는 폴더 값을 쓰고, 폴더에 없으면 화면 값(예전에 브라우저에 있던 값)을 쓴다
 * - 모음 지도는 모음마다 나중에 잰 값
 */
export function mergeVoiceSettings(
  folder: VoiceSettings,
  current: VoiceSettings,
  changed: ReadonlySet<VoiceSettingField>,
): VoiceSettings {
  return {
    target: changed.has('target') ? current.target : (folder.target ?? current.target),
    baseline: changed.has('baseline') ? current.baseline : (folder.baseline ?? current.baseline),
    vowelMap: mergeVowelMaps(folder.vowelMap, current.vowelMap),
  }
}

export function sameVoiceSettings(a: VoiceSettings, b: VoiceSettings): boolean {
  return JSON.stringify(canonical(a)) === JSON.stringify(canonical(b))
}

/** 키 순서를 하나로 맞춘 모양 (같은 값을 다르다고 보지 않게) */
function canonical({ target, baseline, vowelMap }: VoiceSettings): unknown {
  return [
    target && [target.lower, target.upper],
    baseline && [baseline.median, baseline.low, baseline.high, baseline.f2],
    KOREAN_VOWELS.map((vowel) => {
      const e = vowelMap[vowel]
      return e && [e.f1, e.f2, e.f1Spread.lower, e.f1Spread.upper, e.f2Spread.lower, e.f2Spread.upper, e.isF1Uncertain, e.measuredAt]
    }),
  ]
}
