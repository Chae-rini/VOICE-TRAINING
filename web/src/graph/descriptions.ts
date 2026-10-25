import { GraphWindow } from '../dsp/graphWindow'
import { PitchSummary } from '../dsp/pitchSummary'
import { contains, type Range } from '../dsp/range'
import { ResonanceMeter, type ResonanceReading } from '../dsp/voiceMeters'

/**
 * 그림(캔버스)이라 화면 읽기 프로그램이 읽을 것이 없으므로, 그래프·막대가 보여 주는 내용을 말로 만든다
 * (iOS `PitchGraphView`의 accessibilityValue와 같은 문장).
 */

/** "목소리 높이 그래프, 가로축 1분" */
export function graphLabel(window: GraphWindow): string {
  return `목소리 높이 그래프, 가로축 ${PitchSummary.durationLabel(window.duration)}`
}

/** 예: "가로축 1분, 세로축 85에서 225 Hz, 녹음 시작부터 0:35, 목표 범위 135에서 175 Hz, 기준 152 Hz, 지금 152 Hz, 목표 범위 안" */
export function graphDescription(options: {
  frequency: number | null
  window: GraphWindow
  endTime: number
  axis: Range
  target: Range | null
  baselineMedian: number | null
  isReplaying: boolean
}): string {
  const { frequency, window, endTime, axis, target, baselineMedian, isReplaying } = options
  const parts = [
    `가로축 ${PitchSummary.durationLabel(window.duration)}`,
    `세로축 ${Math.trunc(axis.lower)}에서 ${Math.trunc(axis.upper)} Hz`,
  ]
  const elapsed = GraphWindow.timeLabel(endTime - (window.recordingStart ?? window.start))
  if (isReplaying) parts.push(`재생 위치 ${elapsed}`)
  else if (window.recordingStart !== null) parts.push(`녹음 시작부터 ${elapsed}`)
  parts.push(target === null ? '목표 범위 없음' : `목표 범위 ${Math.trunc(target.lower)}에서 ${Math.trunc(target.upper)} Hz`)
  if (baselineMedian !== null) parts.push(`기준 ${Math.round(baselineMedian)} Hz`)
  if (frequency !== null) {
    parts.push(`지금 ${Math.round(frequency)} Hz`)
    if (target !== null) parts.push(contains(target, frequency) ? '목표 범위 안' : '목표 범위 밖')
  } else {
    parts.push('지금 잡힌 목소리 없음')
  }
  return parts.join(', ')
}

/** 예: "음량 −24 dBFS, 공명 밝기 F2 1650 Hz, 기준보다 밝은 쪽" */
export function meterDescription(
  level: number | null,
  isLoud: boolean,
  resonance: ResonanceReading | null,
  baselineF2: number | null,
): string {
  const parts = [level === null ? '음량 없음' : `음량 ${Math.round(level)} dBFS`]
  if (isLoud) parts.push('소리가 꽤 커요')
  if (resonance !== null) {
    let text = `공명 밝기 F2 ${Math.round(resonance.f2)} Hz`
    if (baselineF2 !== null) {
      const position = ResonanceMeter.position(resonance.f2, baselineF2)
      text += position > 0.55 ? ', 기준보다 밝은 쪽' : position < 0.45 ? ', 기준보다 어두운 쪽' : ', 기준과 비슷'
    }
    if (resonance.isUncertain) text += ', 불확실'
    parts.push(text)
  } else {
    parts.push('공명 밝기 없음')
  }
  return parts.join(', ')
}

/** 오래 연습했을 때 목을 쉬어 가라는 안내 (iOS `PracticeLoop.restMessage`). 예: 900초 → "15분 연습했어요. 목을 잠깐 쉬어 주세요." */
export const REST_REMINDER_SECONDS = 15 * 60

export function restMessage(elapsedSeconds: number): string {
  return `${Math.floor(elapsedSeconds / 60)}분 연습했어요. 목을 잠깐 쉬어 주세요.`
}
