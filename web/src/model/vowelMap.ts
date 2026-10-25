import type { PitchReading } from '../dsp/pitchHistory'
import { PitchSummary } from '../dsp/pitchSummary'
import { range, type Range } from '../dsp/range'
import { isF1Uncertain, voicedFormants } from '../dsp/vowelSpace'
import { KOREAN_VOWELS, type KoreanVowel } from '../text/korean'

/** 모음 하나를 잰 결과 */
export interface VowelEntry {
  /** [Hz] 중앙값 */
  readonly f1: number
  readonly f2: number
  /** [Hz] 아래 25%~위 25% — 길게 내는 동안 얼마나 흔들렸는지 */
  readonly f1Spread: Range
  readonly f2Spread: Range
  /** 잴 때 목소리가 높아 F1이 배음 쪽으로 끌렸을 수 있음 */
  readonly isF1Uncertain: boolean
  /** 잰 때 (ISO 8601 글자. 파일에 그대로 저장한다) */
  readonly measuredAt: string
}

/**
 * 내 모음 지도: 7개 단모음을 하나씩 길게 냈을 때 잰 F1·F2 (iOS `Models/VowelMap.swift`).
 * 비교 대상은 이것뿐이다 (성별 평균표는 쓰지 않음, 원칙 3). 모음 이름("아")별로 마지막에 잰 값만 둔다.
 */
export type VowelMap = Readonly<Partial<Record<KoreanVowel, VowelEntry>>>

function isRange(value: unknown): value is Range {
  const r = value as Range | null
  return typeof r === 'object' && r !== null && Number.isFinite(r.lower) && Number.isFinite(r.upper)
}

function isEntry(value: unknown): value is VowelEntry {
  const e = value as VowelEntry | null
  return (
    typeof e === 'object' &&
    e !== null &&
    Number.isFinite(e.f1) &&
    Number.isFinite(e.f2) &&
    isRange(e.f1Spread) &&
    isRange(e.f2Spread) &&
    typeof e.isF1Uncertain === 'boolean' &&
    typeof e.measuredAt === 'string' &&
    !Number.isNaN(Date.parse(e.measuredAt))
  )
}

export const VowelMaps = {
  /** [s] 마이크로 모음 하나를 잴 때의 녹음 길이 */
  recordingSeconds: 3,
  /** [s] 포먼트가 이보다 짧게 잡히면 저장하지 않고 다시 재자고 한다 */
  minimumSeconds: 1,

  /** 같은 모음을 다시 재면 새 값으로 바꾼다. */
  withEntry(map: VowelMap, vowel: KoreanVowel, entry: VowelEntry): VowelMap {
    return { ...map, [vowel]: entry }
  },

  measuredCount(map: VowelMap): number {
    return KOREAN_VOWELS.filter((vowel) => map[vowel] !== undefined).length
  },

  /**
   * 모음 하나를 길게 낸 기록으로 결과를 만든다. 포먼트가 잡힌 시간이 1초보다 짧으면 null.
   * 중앙값을 쓰므로 소리를 내기 시작하고 끝낼 때의 흔들림은 거의 영향을 주지 않는다.
   */
  measure(readings: readonly PitchReading[], date = new Date()): VowelEntry | null {
    const voiced = voicedFormants(readings)
    // 점 사이 간격(분석 간격)으로 포먼트가 잡힌 시간을 어림한다.
    const interval =
      readings.length > 1 ? (readings[readings.length - 1].time - readings[0].time) / (readings.length - 1) : 0
    if (!(voiced.length * interval >= VowelMaps.minimumSeconds)) return null

    const f1s = voiced.map((v) => v.f1).sort((a, b) => a - b)
    const f2s = voiced.map((v) => v.f2).sort((a, b) => a - b)
    const f1 = PitchSummary.percentile(f1s, 0.5)
    const f0 = PitchSummary.percentile(
      voiced.map((v) => v.f0).sort((a, b) => a - b),
      0.5,
    )
    return {
      f1,
      f2: PitchSummary.percentile(f2s, 0.5),
      f1Spread: range(PitchSummary.percentile(f1s, 0.25), PitchSummary.percentile(f1s, 0.75)),
      f2Spread: range(PitchSummary.percentile(f2s, 0.25), PitchSummary.percentile(f2s, 0.75)),
      isF1Uncertain: isF1Uncertain(f1, f0),
      measuredAt: date.toISOString(),
    }
  },

  /** 저장된 값을 읽는다. 없거나 읽을 수 없으면 빈 지도. 모르는 모음·망가진 항목은 빼고 읽는다. */
  decode(value: unknown): VowelMap {
    if (typeof value !== 'object' || value === null) return {}
    const map: Partial<Record<KoreanVowel, VowelEntry>> = {}
    for (const vowel of KOREAN_VOWELS) {
      const entry = (value as Record<string, unknown>)[vowel]
      if (isEntry(entry)) map[vowel] = entry
    }
    return map
  },

  /** 글자(JSON)로 저장된 값을 읽는다 */
  parse(text: string | null): VowelMap {
    if (text === null) return {}
    try {
      return VowelMaps.decode(JSON.parse(text))
    } catch {
      return {}
    }
  },
}
