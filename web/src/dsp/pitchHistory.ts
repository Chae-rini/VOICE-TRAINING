import type { FormantEstimate } from './formantAnalyzer'
import { GraphWindow } from './graphWindow'
import { contains, type Range } from './range'

/** 피치 한 점: 언제(time) 몇 Hz였는지(frequency), 그때의 포먼트(F1·F2)와 소리 크기. */
export interface PitchReading {
  /** [s] 시각 */
  readonly time: number
  /** [Hz] null이면 무음 */
  readonly frequency: number | null
  /** F1·F2. 목소리가 잡히고 또렷한 울림을 두 개 찾았을 때만 있다. */
  readonly formants?: FormantEstimate | null
  /** [dBFS] 이 조각의 소리 크기 (무음 판정과 상관없이 늘 잰다). 이 기기 마이크 기준이라 절대 데시벨이 아니다. */
  readonly level?: number | null
}

/** [s] 분석 간격 (2048샘플 창을 절반씩 밀기, 48 kHz에서 약 21 ms) */
export const READING_INTERVAL = 1024 / 48_000

/** 녹음 한 번 동안의 피치 기록 (iOS `Models/PitchHistory.swift`). 그래프에는 가로축 구간 안의 점이 보인다. */
export class PitchHistory {
  private items: PitchReading[] = []

  /** [s] 보관하는 길이. 녹음을 다시 들으며 처음부터 그리려면 녹음 한 번 길이만큼 남겨 둬야 한다. */
  constructor(readonly retention = 11) {}

  get readings(): readonly PitchReading[] {
    return this.items
  }

  append(newReadings: readonly PitchReading[]): void {
    this.items.push(...newReadings)
    const newest = this.items[this.items.length - 1]
    if (newest === undefined) return
    const cutoff = newest.time - this.retention
    const firstKept = this.items.findIndex((reading) => reading.time >= cutoff)
    if (firstKept > 0) {
      this.items.splice(0, firstKept)
    }
  }

  removeAll(): void {
    this.items = []
  }

  /**
   * 꺾은선으로 이을 유성 구간들. 이웃한 유성 점 사이가 `maxGap` [s]보다 벌어지면 선을 끊는다.
   * 분석 간격이 약 21ms라서, 0.05초로 두면 점이 하나 빠진 곳은 잇고 그보다 긴 무음은 비워 둔다.
   * `within`을 주면 그 시간 안의 점만 쓴다.
   */
  voicedSegments(maxGap = 0.05, within: Range | null = null): PitchReading[][] {
    const segments: PitchReading[][] = []
    let current: PitchReading[] = []
    for (const reading of this.items) {
      if (reading.frequency === null) continue
      if (within !== null && !contains(within, reading.time)) continue
      const last = current[current.length - 1]
      if (last !== undefined && reading.time - last.time > maxGap) {
        segments.push(current)
        current = []
      }
      current.push(reading)
    }
    if (current.length > 0) {
      segments.push(current)
    }
    return segments
  }

  /**
   * 그래프에 그릴 유성 구간들 (`window` 안, `end` 시각까지). `width`: 그래프 가로 폭의 픽셀 수.
   * 가로축이 길어 한 픽셀 열에 점이 두 개 넘게 몰리면, 열마다 한 점(그 열의 목소리 높이 평균)으로 묶는다.
   * 묶은 칸 사이에 목소리 없는 칸이 끼면 선을 끊는다.
   */
  displaySegments(window: GraphWindow, end: number, width: number): PitchReading[][] {
    // 흐르는 그래프의 왼쪽 끝에서 선이 끊겨 보이지 않게 조금 앞부터 그린다 (그래프 밖은 잘라 낸다).
    const span: Range = { lower: window.start - 0.5, upper: Math.max(window.start - 0.5, Math.min(end, window.end)) }
    const bucket = window.duration / Math.max(width, 1) // [s] 한 픽셀 열의 길이
    if (!(bucket > READING_INTERVAL * 2)) {
      return this.voicedSegments(0.05, span)
    }

    const segments: PitchReading[][] = []
    let current: PitchReading[] = []
    let bucketIndex: number | null = null
    let sum = 0
    let count = 0
    const closeBucket = () => {
      if (bucketIndex === null || count === 0) return
      const point: PitchReading = { time: window.start + (bucketIndex + 0.5) * bucket, frequency: sum / count }
      const last = current[current.length - 1]
      if (last !== undefined && point.time - last.time > bucket * 1.5) {
        segments.push(current)
        current = []
      }
      current.push(point)
    }
    for (const reading of this.readingsIn(span)) {
      if (reading.frequency === null) continue
      const index = Math.floor((reading.time - window.start) / bucket)
      if (index !== bucketIndex) {
        closeBucket()
        bucketIndex = index
        sum = 0
        count = 0
      }
      sum += reading.frequency
      count += 1
    }
    closeBucket()
    if (current.length > 0) {
      segments.push(current)
    }
    return segments
  }

  /** `span` 시간 안의 점들. 기록은 시간 순서라 이진 탐색으로 시작 위치를 찾는다 (화면이 초당 수십 번 부른다). */
  readingsIn(span: Range): PitchReading[] {
    let low = 0
    let high = this.items.length
    while (low < high) {
      const middle = (low + high) >> 1
      if (this.items[middle].time < span.lower) {
        low = middle + 1
      } else {
        high = middle
      }
    }
    let end = low
    while (end < this.items.length && this.items[end].time <= span.upper) {
      end += 1
    }
    return this.items.slice(low, end)
  }

  /** `time` 직전의 피치 [Hz]. `tolerance` [s]보다 오래된 값이거나 무음이면 null. */
  frequencyAt(time: number, tolerance = 0.3): number | null {
    for (let i = this.items.length - 1; i >= 0; i--) {
      const reading = this.items[i]
      if (reading.time <= time && reading.frequency !== null) {
        return time - reading.time <= tolerance ? reading.frequency : null
      }
    }
    return null
  }
}

/** 그래프가 지금 무엇을 보여 주는지: 가로축 구간과 "지금"(녹음 중) 또는 재생 위치. */
export type GraphClock =
  /** 녹음 중: 실제 지금. 가로축은 최근 `duration`초 (오른쪽 끝이 지금). `start`: 녹음을 시작한 시각 */
  | { readonly kind: 'live'; readonly start: number; readonly duration: number; readonly round: number | null }
  /** 멈춘 화면: 마지막 녹음의 구간을 그대로 보여 준다. `at`: 녹음이 끝난 시각. 녹음이 없으면 둘 다 null */
  | { readonly kind: 'frozen'; readonly window: GraphWindow | null; readonly at: number | null }
  /** 녹음을 다시 듣는 중: 녹음 구간 전체를 보이고, 재생 위치가 녹음 첫 소리(`takeStart`)부터 재생된 만큼 움직인다 */
  | { readonly kind: 'replay'; readonly window: GraphWindow; readonly takeStart: number; readonly playbackStart: number }

/** 시간에 따라 움직이는지 (움직일 때만 화면을 계속 다시 그린다) */
export function clockIsMoving(clock: GraphClock): boolean {
  return clock.kind !== 'frozen'
}

/** "지금"의 시각 [s]: 녹음 중이면 지금, 다시 듣는 중이면 재생 위치, 멈췄으면 녹음이 끝난 시각 */
export function clockEndTime(clock: GraphClock, now: number): number {
  switch (clock.kind) {
    case 'live':
      return now
    case 'frozen':
      return clock.at ?? now
    case 'replay':
      return clock.takeStart + (now - clock.playbackStart)
  }
}

/** 가로축 구간. 아직 녹음이 없으면 null */
export function clockWindow(clock: GraphClock, now: number): GraphWindow | null {
  switch (clock.kind) {
    case 'live':
      return GraphWindow.live(clock.start, now, clock.duration, clock.round)
    case 'frozen':
      return clock.window
    case 'replay':
      return clock.window
  }
}
