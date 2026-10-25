import { FormantAnalyzer } from './formantAnalyzer'
import { PitchDetector, rootMeanSquare } from './pitchDetector'
import type { PitchReading } from './pitchHistory'
import { LevelMeter } from './voiceMeters'

/**
 * 마이크에서 조각조각 들어오는 소리를 연습할 때의 방식(2048샘플 창을 절반씩 겹쳐 밀기)으로 분석한다
 * (iOS `AudioInputManager.swift`의 `PitchTapProcessor`). 조각 크기가 어떻든 `analyzeSamples`와 같은 창을 본다.
 * 분석 스레드(Web Worker) 안에서 쓴다. 화면과 상관없는 순수 계산이라 테스트로 확인한다.
 */
export class StreamAnalyzer {
  readonly sampleRate: number
  /** [샘플] 다음 창으로 미는 간격 (48 kHz에서 약 21 ms마다 한 점) */
  readonly hopLength: number
  private readonly detector: PitchDetector
  private readonly formantAnalyzer: FormantAnalyzer
  /** 아직 분석하지 않은 소리. 앞 `count`개만 쓴다. */
  private pending: Float32Array
  private count = 0
  /** [s] pending[0] 샘플의 시각 */
  private pendingStartTime = 0

  constructor(sampleRate: number) {
    this.sampleRate = sampleRate
    this.detector = new PitchDetector(sampleRate)
    this.formantAnalyzer = new FormantAnalyzer(sampleRate)
    this.hopLength = this.detector.frameLength / 2
    this.pending = new Float32Array(this.detector.frameLength * 2)
  }

  get frameLength(): number {
    return this.detector.frameLength
  }

  /**
   * 소리 조각 하나를 더하고, 창이 찰 때마다 점을 만든다. `chunkStartTime` [s]: 조각 첫 샘플의 시각.
   * iOS처럼 남은 소리가 없을 때만 조각의 시각으로 다시 맞추고, 그 밖에는 샘플 수로 시각을 센다.
   */
  push(chunk: Float32Array, chunkStartTime: number): PitchReading[] {
    if (this.count === 0) {
      this.pendingStartTime = chunkStartTime
    }
    if (this.count + chunk.length > this.pending.length) {
      const grown = new Float32Array(Math.max(this.pending.length * 2, this.count + chunk.length))
      grown.set(this.pending.subarray(0, this.count))
      this.pending = grown
    }
    this.pending.set(chunk, this.count)
    this.count += chunk.length

    const frameLength = this.detector.frameLength
    const readings: PitchReading[] = []
    while (this.count >= frameLength) {
      const frame = this.pending.subarray(0, frameLength)
      const estimate = this.detector.detect(frame)
      readings.push({
        // 창 한가운데 시각을 그 점의 시각으로 쓴다.
        time: this.pendingStartTime + frameLength / 2 / this.sampleRate,
        frequency: estimate?.frequency ?? null,
        // 목소리가 잡힌 조각에서만 포먼트를 잰다.
        formants: estimate === null ? null : this.formantAnalyzer.estimate(frame),
        level: LevelMeter.dBFS(rootMeanSquare(frame)),
      })
      this.pending.copyWithin(0, this.hopLength, this.count)
      this.count -= this.hopLength
      this.pendingStartTime += this.hopLength / this.sampleRate
    }
    return readings
  }

  /** 남은 소리를 버린다 (녹음을 멈췄다가 다시 시작할 때) */
  reset(): void {
    this.count = 0
  }
}
