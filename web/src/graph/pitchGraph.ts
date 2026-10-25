import type { GraphWindow } from '../dsp/graphWindow'
import type { PitchHistory, PitchReading } from '../dsp/pitchHistory'
import { graphRange, isBeyond, position, ticks } from '../dsp/pitchScale'
import { contains, type Range } from '../dsp/range'

/**
 * [높이] 그래프 그리기 (iOS `PitchGraphView.drawGraph`를 Canvas 2D로 옮겼다).
 * 가로축은 들려줄 길이(오른쪽 끝 = 지금), 세로축은 목표 범위 ±50 Hz의 반음 눈금이다.
 * 목표 범위 안은 굵은 분홍, 밖은 가는 회색, 세로축 밖으로 나간 부분은 위·아래 끝의 회색 점선이다.
 */

export interface Point {
  readonly x: number
  readonly y: number
}

export interface PlotRect {
  readonly x: number
  readonly y: number
  readonly width: number
  readonly height: number
}

/** 왼쪽은 Hz 숫자(세 자리), 아래는 시간 표시 자리로 비워 둔다. 그래프가 넓게 보이게 양옆 여백은 좁게. */
export function plotRect(width: number, height: number): PlotRect {
  return { x: 34, y: 12, width: width - 42, height: height - 36 }
}

/**
 * 그래프 높이 [px]: 쓸 수 있는 높이의 45%(대본 읽기 모드는 33%).
 * 작은 화면에서도 너무 낮지 않게(220·150), 큰 화면에서도 아래 문장 자리를 남기게(380·280) 막는다 (iOS와 같다).
 */
export function graphHeight(available: number, isCompact: boolean): number {
  return isCompact ? Math.min(Math.max(available * 0.33, 150), 280) : Math.min(Math.max(available * 0.45, 220), 380)
}

/** 꺾은선 모양: 선분은 [시작, 끝], 세로축 밖은 이어진 점선 (조각마다 새로 시작하면 점선 무늬가 실선처럼 보인다) */
export interface CurveShapes {
  readonly inside: [Point, Point][]
  readonly outside: [Point, Point][]
  readonly beyond: Point[][]
  readonly lonelyInside: Point[]
  readonly lonelyOutside: Point[]
}

/**
 * 유성 구간들을 선분으로 나눈다. 선분마다 두 끝점의 가운데 높이가 목표 범위 안이면 안쪽, 밖이면 바깥쪽.
 * 두 끝점이 모두 세로축 같은 쪽 밖이면 끝에 붙인 점선. 앞뒤로 이어진 점이 없는 외톨이 점은 작은 점으로.
 */
export function buildCurve(
  segments: readonly (readonly PitchReading[])[],
  toPoint: (reading: PitchReading) => Point | null,
  axis: Range,
  target: Range | null,
): CurveShapes {
  const shapes: CurveShapes = { inside: [], outside: [], beyond: [], lonelyInside: [], lonelyOutside: [] }
  const inTarget = (frequency: number) => target !== null && contains(target, frequency)
  let beyondLine: Point[] | null = null
  for (const segment of segments) {
    if (segment.length === 1) {
      const only = segment[0]
      const p = toPoint(only)
      if (p !== null && only.frequency !== null) {
        ;(inTarget(only.frequency) ? shapes.lonelyInside : shapes.lonelyOutside).push(p)
      }
      continue
    }
    for (let i = 1; i < segment.length; i++) {
      const previous = segment[i - 1]
      const next = segment[i]
      const a = toPoint(previous)
      const b = toPoint(next)
      if (a === null || b === null || previous.frequency === null || next.frequency === null) continue
      if (isBeyond(previous.frequency, next.frequency, axis)) {
        const last = beyondLine?.[beyondLine.length - 1]
        if (beyondLine !== null && last !== undefined && last.x === a.x && last.y === a.y) {
          beyondLine.push(b)
        } else {
          beyondLine = [a, b]
          shapes.beyond.push(beyondLine)
        }
      } else if (inTarget((previous.frequency + next.frequency) / 2)) {
        shapes.inside.push([a, b])
      } else {
        shapes.outside.push([a, b])
      }
    }
  }
  return shapes
}

export interface GraphColors {
  readonly voice: string
  readonly inactive: string
  readonly target: string
  readonly reference: string
  readonly secondary: string
  readonly primary: string
}

export interface GraphScene {
  readonly history: PitchHistory
  readonly window: GraphWindow
  /** [s] "지금": 녹음 중이면 지금, 멈췄으면 끝난 시각, 다시 듣는 중이면 재생 위치 */
  readonly endTime: number
  readonly target: Range | null
  readonly baselineMedian: number | null
  /** 다시 듣는 중: 녹음 전체를 그리고, 아직 재생하지 않은 뒷부분은 흐리게 */
  readonly isReplaying: boolean
}

/** 목표 범위 띠처럼 넓게 칠할 때의 진하기 (iOS `UllimColor.bandOpacity`) */
const BAND_OPACITY = 0.18
const INSIDE_WIDTH = 3.5
const OUTSIDE_WIDTH = 2
const DOT_SIZE = 5
const OUTSIDE_DOT_SIZE = 3.5

/** 그래프 한 장을 그린다. `width`·`height`는 CSS 픽셀, `pixelRatio`는 화면 밀도 (선명하게 그리려고 캔버스를 키운다). */
export function drawPitchGraph(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  pixelRatio: number,
  scene: GraphScene,
  colors: GraphColors,
  fontFamily: string,
): void {
  const { window, endTime, target, baselineMedian } = scene
  ctx.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0)
  ctx.clearRect(0, 0, width, height)

  const plot = plotRect(width, height)
  const axis = graphRange(target)
  const x = (time: number) => plot.x + window.position(time) * plot.width
  // 세로축 밖의 높이는 위·아래 끝에 붙여 점선으로 그린다 (그래프에서 사라지지 않게, 큰 숫자에는 실제 값이 보인다).
  const y = (frequency: number) =>
    plot.y + plot.height - Math.min(Math.max(position(frequency, axis), 0), 1) * plot.height
  const smallFont = `11px ${fontFamily}`
  const labelFont = `500 11px ${fontFamily}`

  // 목표 범위 띠
  if (target !== null) {
    ctx.globalAlpha = BAND_OPACITY
    ctx.fillStyle = colors.target
    ctx.fillRect(plot.x, y(target.upper), plot.width, y(target.lower) - y(target.upper))
    ctx.globalAlpha = 1
  }

  // Hz 눈금: 세로축이 목표 범위 둘레로 좁아서 눈금을 5개 이상 둔다 (예: 90·100·125·150·175·200).
  ctx.font = smallFont
  ctx.textAlign = 'right'
  ctx.textBaseline = 'middle'
  for (const frequency of ticks(axis, 5)) {
    line(ctx, plot.x, y(frequency), plot.x + plot.width, y(frequency), colors.secondary, 0.25, 0.5)
    ctx.fillStyle = colors.secondary
    ctx.fillText(String(Math.trunc(frequency)), plot.x - 6, y(frequency))
  }

  // 시간 눈금: 녹음을 시작한 때부터 몇 분 몇 초인지 ("0:30"). 양 끝 글자는 그래프 밖으로 나가지 않게 붙인다.
  ctx.textBaseline = 'top'
  for (const tick of window.ticks) {
    const tickX = x(tick.time)
    line(ctx, tickX, plot.y, tickX, plot.y + plot.height, colors.secondary, 0.15, 0.5)
    ctx.textAlign = tickX < plot.x + 12 ? 'left' : tickX > plot.x + plot.width - 12 ? 'right' : 'center'
    ctx.fillStyle = colors.secondary
    ctx.fillText(tick.label, tickX, plot.y + plot.height + 6)
  }

  // 내 기준 목소리(중앙값): 보라 점선과 "기준" 글자. 세로축(목표 범위 ±50 Hz) 밖이면 긋지 않는다.
  if (baselineMedian !== null && contains(axis, baselineMedian)) {
    ctx.setLineDash([5, 4])
    line(ctx, plot.x, y(baselineMedian), plot.x + plot.width, y(baselineMedian), colors.reference, 0.8, 1.5)
    ctx.setLineDash([])
    ctx.font = labelFont
    ctx.textAlign = 'left'
    ctx.textBaseline = 'bottom'
    ctx.fillStyle = colors.reference
    ctx.fillText('기준', plot.x + 4, y(baselineMedian) - 2)
  }

  // 녹음 시작선: 첫 녹음은 실선 "시작", 반복 루프에서 다시 녹음한 것은 점선 "2번째"처럼.
  if (window.showsStartLine && window.recordingStart !== null) {
    const startX = Math.max(x(window.recordingStart), plot.x)
    if (window.isRoundBoundary) ctx.setLineDash([4, 3])
    line(ctx, startX, plot.y, startX, plot.y + plot.height, colors.secondary, 0.8, 1.5)
    ctx.setLineDash([])
    // 막 시작해 선이 오른쪽 끝 가까이 있으면 글자를 선 왼쪽에 붙인다 (그래프 밖으로 나가지 않게).
    const labelOnLeft = startX > plot.x + plot.width - 44
    ctx.font = labelFont
    ctx.textAlign = labelOnLeft ? 'right' : 'left'
    ctx.textBaseline = 'top'
    ctx.fillStyle = colors.secondary
    ctx.fillText(window.startLabel, labelOnLeft ? startX - 4 : startX + 4, plot.y + 2)
  }

  // 피치 꺾은선: 화면 폭보다 촘촘한 점은 같은 픽셀 열마다 하나로 묶는다 (3분이면 점이 8천 개가 넘는다).
  const segments = scene.history.displaySegments(window, scene.isReplaying ? window.end : endTime, plot.width * pixelRatio)
  const curve = buildCurve(
    segments,
    (reading) => (reading.frequency === null ? null : { x: x(reading.time), y: y(reading.frequency) }),
    axis,
    target,
  )

  ctx.save()
  // 가로축 구간 밖(흘러간 앞부분)은 잘라 낸다.
  ctx.beginPath()
  ctx.rect(plot.x - DOT_SIZE, plot.y - DOT_SIZE, plot.width + 2 * DOT_SIZE, plot.height + 2 * DOT_SIZE)
  ctx.clip()
  if (!scene.isReplaying) {
    drawCurve(ctx, curve, colors)
  } else {
    // 다시 듣는 중: 재생한 앞부분은 그대로, 아직 재생하지 않은 뒷부분은 흐리게, 재생 위치에 세로선
    const playheadX = Math.min(Math.max(x(endTime), plot.x), plot.x + plot.width)
    ctx.save()
    ctx.beginPath()
    ctx.rect(0, 0, playheadX, height)
    ctx.clip()
    drawCurve(ctx, curve, colors)
    ctx.restore()
    ctx.save()
    ctx.beginPath()
    ctx.rect(playheadX, 0, width - playheadX, height)
    ctx.clip()
    ctx.globalAlpha = 0.3
    drawCurve(ctx, curve, colors)
    ctx.restore()
    line(ctx, playheadX, plot.y, playheadX, plot.y + plot.height, colors.primary, 0.6, 1.5)
  }
  ctx.restore()
}

function drawCurve(ctx: CanvasRenderingContext2D, curve: CurveShapes, colors: GraphColors): void {
  ctx.lineCap = 'round'
  ctx.lineJoin = 'round'

  ctx.strokeStyle = colors.inactive
  ctx.lineWidth = OUTSIDE_WIDTH
  strokeSegments(ctx, curve.outside)

  ctx.setLineDash([2, 4])
  ctx.beginPath()
  for (const polyline of curve.beyond) {
    ctx.moveTo(polyline[0].x, polyline[0].y)
    for (const p of polyline.slice(1)) ctx.lineTo(p.x, p.y)
  }
  ctx.stroke()
  ctx.setLineDash([])

  ctx.strokeStyle = colors.voice
  ctx.lineWidth = INSIDE_WIDTH
  strokeSegments(ctx, curve.inside)

  fillDots(ctx, curve.lonelyOutside, OUTSIDE_DOT_SIZE, colors.inactive)
  fillDots(ctx, curve.lonelyInside, DOT_SIZE, colors.voice)
}

function strokeSegments(ctx: CanvasRenderingContext2D, segments: readonly [Point, Point][]): void {
  ctx.beginPath()
  for (const [a, b] of segments) {
    ctx.moveTo(a.x, a.y)
    ctx.lineTo(b.x, b.y)
  }
  ctx.stroke()
}

function fillDots(ctx: CanvasRenderingContext2D, points: readonly Point[], size: number, color: string): void {
  ctx.fillStyle = color
  ctx.beginPath()
  for (const p of points) {
    ctx.moveTo(p.x + size / 2, p.y)
    ctx.arc(p.x, p.y, size / 2, 0, 2 * Math.PI)
  }
  ctx.fill()
}

function line(
  ctx: CanvasRenderingContext2D,
  x1: number,
  y1: number,
  x2: number,
  y2: number,
  color: string,
  opacity: number,
  width: number,
): void {
  ctx.save()
  ctx.globalAlpha = opacity
  ctx.strokeStyle = color
  ctx.lineWidth = width
  ctx.beginPath()
  ctx.moveTo(x1, y1)
  ctx.lineTo(x2, y2)
  ctx.stroke()
  ctx.restore()
}
