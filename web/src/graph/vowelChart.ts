import type { PitchReading } from '../dsp/pitchHistory'
import { VowelSpace, type VowelPoint } from '../dsp/vowelSpace'
import type { VowelMap } from '../model/vowelMap'
import { KOREAN_VOWELS, type KoreanVowel } from '../text/korean'
import type { GraphColors, PlotRect } from './pitchGraph'

/**
 * 모음 지도 그리기 (iOS `VowelChartView.draw`를 Canvas 2D로 옮겼다).
 * 가로 F2(왼쪽이 혀 앞쪽), 세로 F1(위가 입을 좁게). 지금 내는 소리는 큰 분홍 점, 최근 1.5초는 흐린 꼬리,
 * 내가 잰 모음(내 모음 지도)은 보라 원과 글자. 성별 평균 같은 기준 위치는 그리지 않는다 (원칙 3).
 */

/** [s] 지금 점을 정할 때 모으는 길이 (흔들림 줄이기) */
export const CURRENT_WINDOW = 0.3
/** [s] 꼬리 길이 */
export const TRAIL_WINDOW = 1.5
/** [px] 지도 높이 */
export const CHART_HEIGHT = 320

/** 왼쪽은 F1 숫자, 아래는 F2 숫자와 방향 안내 자리로 비워 둔다. */
export function vowelPlotRect(width: number, height: number): PlotRect {
  return { x: 44, y: 24, width: width - 56, height: height - 64 }
}

export interface VowelScene {
  readonly current: VowelPoint | null
  readonly trail: readonly PitchReading[]
  /** [s] 꼬리의 끝(지금 또는 재생 위치) */
  readonly end: number
  readonly map: VowelMap
  readonly selected: KoreanVowel
}

/** 차이를 부호와 함께: +12, -30, 0 (iOS와 같은 표기) */
export function signedHz(difference: number): string {
  const value = Math.round(difference)
  return value > 0 ? `+${value}` : `${value}`
}

/** 내가 잰 같은 모음과의 차이 (어느 쪽이 낫다는 뜻이 아니라 얼마나 다른지만). 그 모음을 아직 안 쟀으면 null */
export function comparisonText(current: VowelPoint | null, map: VowelMap, selected: KoreanVowel): string | null {
  const saved = map[selected]
  if (current === null || saved === undefined) return null
  return `내 ‘${selected}’와 비교 · F1 ${signedHz(current.f1 - saved.f1)} · F2 ${signedHz(current.f2 - saved.f2)} Hz`
}

/** 화면 읽기 프로그램용 설명: 지금 점과 내가 잰 모음들의 숫자 */
export function vowelChartDescription(current: VowelPoint | null, map: VowelMap): string {
  const now =
    current === null
      ? '지금 잡힌 모음이 없어요.'
      : `지금 F1 ${Math.round(current.f1)} Hz, F2 ${Math.round(current.f2)} Hz${current.isF1Uncertain ? ', F1은 정확하지 않을 수 있어요' : ''}.`
  const measured = KOREAN_VOWELS.flatMap((vowel) => {
    const entry = map[vowel]
    return entry === undefined ? [] : [`${vowel} F1 ${Math.round(entry.f1)}, F2 ${Math.round(entry.f2)}`]
  })
  return measured.length === 0 ? now : `${now} 내 모음 지도 ${measured.length}개: ${measured.join(' · ')} Hz.`
}

export function drawVowelChart(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  pixelRatio: number,
  scene: VowelScene,
  colors: GraphColors,
  fontFamily: string,
): void {
  ctx.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0)
  ctx.clearRect(0, 0, width, height)
  const plot = vowelPlotRect(width, height)
  const point = (f1: number, f2: number) => {
    const unit = VowelSpace.position(f1, f2)
    return { x: plot.x + unit.x * plot.width, y: plot.y + unit.y * plot.height }
  }
  const smallFont = `11px ${fontFamily}`
  const boldFont = `600 11px ${fontFamily}`
  const label = (text: string, x: number, y: number, align: CanvasTextAlign, baseline: CanvasTextBaseline, bold = false) => {
    ctx.font = bold ? boldFont : smallFont
    ctx.fillStyle = colors.secondary
    ctx.textAlign = align
    ctx.textBaseline = baseline
    ctx.fillText(text, x, y)
  }
  const line = (x1: number, y1: number, x2: number, y2: number) => {
    ctx.beginPath()
    ctx.moveTo(x1, y1)
    ctx.lineTo(x2, y2)
    ctx.stroke()
  }

  // 눈금: 세로축 F1, 가로축 F2
  ctx.strokeStyle = colors.secondary
  ctx.globalAlpha = 0.25
  ctx.lineWidth = 0.5
  for (const f1 of VowelSpace.f1Ticks) {
    const y = point(f1, VowelSpace.f2Range.lower).y
    line(plot.x, y, plot.x + plot.width, y)
  }
  for (const f2 of VowelSpace.f2Ticks) {
    const x = point(VowelSpace.f1Range.lower, f2).x
    line(x, plot.y, x, plot.y + plot.height)
  }
  ctx.globalAlpha = 1
  for (const f1 of VowelSpace.f1Ticks) {
    label(String(f1), plot.x - 6, point(f1, VowelSpace.f2Range.lower).y, 'right', 'middle')
  }
  for (const f2 of VowelSpace.f2Ticks) {
    label(String(f2), point(VowelSpace.f1Range.lower, f2).x, plot.y + plot.height + 4, 'center', 'top')
  }

  // 축 이름과 방향 안내 (입과 혀의 움직임일 뿐, 좋고 나쁨이 아니다)
  const bottom = plot.y + plot.height
  label('F1', plot.x - 6, plot.y - 12, 'right', 'middle', true)
  label('입 좁게', plot.x + 4, plot.y - 4, 'left', 'bottom')
  label('입 크게', plot.x + 4, bottom - 4, 'left', 'bottom')
  label('← 혀 앞쪽', plot.x, bottom + 22, 'left', 'top')
  label('F2', plot.x + plot.width / 2, bottom + 22, 'center', 'top', true)
  label('혀 뒤쪽 →', plot.x + plot.width, bottom + 22, 'right', 'top')

  // 내 모음 지도: 잰 모음마다 보라 원과 글자. 길게 내는 동안 흔들린 범위(25%~75%)는 옅은 십자로.
  // 잴 때 F1이 불확실했으면 원을 점선으로 그린다.
  for (const vowel of KOREAN_VOWELS) {
    const entry = scene.map[vowel]
    if (entry === undefined) continue
    const p = point(entry.f1, entry.f2)
    ctx.strokeStyle = colors.reference
    ctx.globalAlpha = 0.35
    ctx.lineWidth = 1.5
    line(point(entry.f1, entry.f2Spread.upper).x, p.y, point(entry.f1, entry.f2Spread.lower).x, p.y)
    line(p.x, point(entry.f1Spread.lower, entry.f2).y, p.x, point(entry.f1Spread.upper, entry.f2).y)

    const isSelected = vowel === scene.selected
    const radius = isSelected ? 15 : 12
    ctx.beginPath()
    ctx.arc(p.x, p.y, radius, 0, 2 * Math.PI)
    ctx.fillStyle = colors.reference
    ctx.globalAlpha = isSelected ? 0.22 : 0.1
    ctx.fill()
    ctx.globalAlpha = 1
    ctx.lineWidth = isSelected ? 2 : 1.2
    ctx.setLineDash(entry.isF1Uncertain ? [3, 3] : [])
    ctx.stroke()
    ctx.setLineDash([])
    ctx.font = `600 12px ${fontFamily}`
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillText(vowel, p.x, p.y)
  }

  // 꼬리: 최근 1.5초. 오래된 점일수록 흐리게
  ctx.fillStyle = colors.inactive
  for (const reading of scene.trail) {
    if (!reading.formants) continue
    const p = point(reading.formants.f1.frequency, reading.formants.f2.frequency)
    const fade = 1 - (scene.end - reading.time) / TRAIL_WINDOW
    ctx.globalAlpha = Math.max(0.08, 0.5 * fade)
    ctx.beginPath()
    ctx.arc(p.x, p.y, 2.5, 0, 2 * Math.PI)
    ctx.fill()
  }
  ctx.globalAlpha = 1

  // 지금 점. F1이 불확실하면 속이 빈 점선 원으로 그린다.
  const current = scene.current
  if (current !== null) {
    const p = point(current.f1, current.f2)
    ctx.beginPath()
    ctx.arc(p.x, p.y, 9, 0, 2 * Math.PI)
    if (current.isF1Uncertain) {
      ctx.strokeStyle = colors.voice
      ctx.lineWidth = 2
      ctx.setLineDash([3, 3])
      ctx.stroke()
      ctx.setLineDash([])
    } else {
      ctx.fillStyle = colors.voice
      ctx.fill()
    }
  }
}
