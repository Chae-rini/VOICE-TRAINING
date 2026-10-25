import type { Range } from './range'

/** 한 프레임에서 찾은 피치. */
export interface PitchEstimate {
  /** 기본주파수 F0 [Hz] */
  readonly frequency: number
  /** 0~1. 1에 가까울수록 주기성이 뚜렷하다 (= 1 − d′(τ)). */
  readonly confidence: number
}

/** [Hz] 이 밖의 결과는 버린다 */
export const FREQUENCY_RANGE: Range = { lower: 70, upper: 400 }

/** RMS: √(Σx²/N) */
export function rootMeanSquare(frame: ArrayLike<number>): number {
  let sum = 0
  for (let i = 0; i < frame.length; i++) {
    sum += frame[i] * frame[i]
  }
  return frame.length > 0 ? Math.sqrt(sum / frame.length) : 0
}

/**
 * YIN 피치 검출기. iOS 앱 `Audio/PitchDetector.swift`를 그대로 옮겼다 (같은 소리에 같은 Hz가 나와야 한다).
 *
 * 참고 논문: A. de Cheveigné & H. Kawahara,
 * "YIN, a fundamental frequency estimator for speech and music", JASA 111(4), 2002.
 * 논문의 1~4단계를 구현했다. 5~6단계(주변 프레임과 비교해 다듬기)는 생략.
 *
 * 내부 작업 버퍼를 재사용하므로 한 인스턴스를 여러 곳에서 동시에 쓰면 안 된다.
 */
export class PitchDetector {
  readonly sampleRate: number
  /** 한 번에 분석하는 샘플 수 */
  readonly frameLength: number

  /**
   * d′(τ)가 이 값 아래로 내려가야 "주기적인 소리"로 인정한다. 논문 권장은 0.10~0.15.
   * 실제 녹음 32개로 Praat와 비교했을 때 0.20이 큰 오류를 늘리지 않으면서 소리 시작·끝을 덜 놓쳤다.
   */
  threshold = 0.2
  /** RMS 음량이 이보다 작으면 무음. 약 −54 dBFS. */
  minimumRMS = 0.002

  /** 가장 낮은 주파수(70Hz)의 한 주기 [샘플] */
  private readonly maxLag: number
  /** 차이를 합산하는 구간 W [샘플] */
  private readonly windowLength: number

  private readonly samples: Float64Array
  /** r(τ) */
  private readonly correlation: Float64Array
  /** d(τ) */
  private readonly difference: Float64Array
  /** d′(τ) */
  private readonly normalized: Float64Array

  constructor(sampleRate: number, frameLength?: number) {
    const maxLag = Math.ceil(sampleRate / FREQUENCY_RANGE.lower)
    // 70Hz 한 주기를 비교하려면 W ≥ maxLag 여야 한다. 48kHz에서는 2048이면 충분하다.
    const length = frameLength ?? Math.max(2048, 2 * maxLag + 2)
    // τ = maxLag + 1까지 계산해 둬야 maxLag에서도 4단계 보간을 할 수 있다.
    const windowLength = length - (maxLag + 1)
    if (windowLength < maxLag) {
      throw new Error('frameLength가 너무 짧습니다')
    }

    this.sampleRate = sampleRate
    this.frameLength = length
    this.maxLag = maxLag
    this.windowLength = windowLength
    this.samples = new Float64Array(length)
    this.correlation = new Float64Array(maxLag + 2)
    this.difference = new Float64Array(maxLag + 2)
    this.normalized = new Float64Array(maxLag + 2)
  }

  /** `frame`(길이 = frameLength)의 피치를 찾는다. 무음이거나 믿을 수 없으면 null. */
  detect(frame: ArrayLike<number>): PitchEstimate | null {
    if (frame.length !== this.frameLength) {
      throw new Error(`frame 길이는 ${this.frameLength}이어야 합니다 (받은 길이 ${frame.length})`)
    }

    // 0단계 — 음량 확인: 너무 조용하면 계산할 필요 없이 무음.
    if (rootMeanSquare(frame) < this.minimumRMS) {
      return null
    }

    for (let i = 0; i < this.frameLength; i++) {
      this.samples[i] = frame[i]
    }

    this.computeDifference()
    this.computeCumulativeMeanNormalizedDifference()
    // 주기성이 약하면(숨소리·잡음) 무음으로 처리한다.
    const lag = this.findFirstDip()
    if (lag === null) {
      return null
    }

    const frequency = this.sampleRate / this.refineLag(lag)
    if (frequency < FREQUENCY_RANGE.lower || frequency > FREQUENCY_RANGE.upper) {
      return null
    }
    return { frequency, confidence: Math.min(1, Math.max(0, 1 - this.normalized[lag])) }
  }

  /**
   * 1단계 — 차이 함수 (difference function)
   *
   *     d(τ) = Σ_{j=0}^{W−1} (x_j − x_{j+τ})²  =  e₀ + e_τ − 2·r(τ)
   *
   * e₀ = Σ x_j² (앞 구간의 에너지), e_τ = Σ x_{j+τ}² (τ만큼 민 구간의 에너지), r(τ) = Σ x_j·x_{j+τ} (자기상관).
   * iOS는 r(τ)를 vDSP 상관 연산으로 구하고, 여기서는 같은 식을 반복문으로 계산한다.
   */
  private computeDifference(): void {
    const { samples, correlation, difference, windowLength, maxLag } = this
    for (let lag = 0; lag <= maxLag + 1; lag++) {
      let sum = 0
      for (let j = 0; j < windowLength; j++) {
        sum += samples[j + lag] * samples[j]
      }
      correlation[lag] = sum
    }

    const e0 = correlation[0]
    let shiftedEnergy = e0
    for (let lag = 0; lag <= maxLag + 1; lag++) {
      if (lag > 0) {
        // 구간이 한 칸 밀리면 맨 앞 샘플이 빠지고 맨 뒤 샘플이 새로 들어온다.
        const leaving = samples[lag - 1]
        const entering = samples[lag - 1 + windowLength]
        shiftedEnergy += entering * entering - leaving * leaving
      }
      // 반올림 오차로 아주 작은 음수가 나올 수 있어 0에서 자른다.
      difference[lag] = Math.max(0, e0 + shiftedEnergy - 2 * correlation[lag])
    }
  }

  /**
   * 2단계 — 누적 평균 정규화 차이 (cumulative mean normalized difference)
   *
   *     d′(0) = 1,   d′(τ) = d(τ) / [ (1/τ) · Σ_{j=1}^{τ} d(j) ]
   */
  private computeCumulativeMeanNormalizedDifference(): void {
    const { difference, normalized, maxLag } = this
    normalized[0] = 1
    let runningSum = 0
    for (let lag = 1; lag <= maxLag + 1; lag++) {
      runningSum += difference[lag]
      normalized[lag] = runningSum > 0 ? (difference[lag] * lag) / runningSum : 1
    }
  }

  /**
   * 3단계 — 절대 임계값 (absolute threshold)
   *
   * d′(τ)가 threshold 아래로 처음 내려가는 τ를 찾고, 그 골짜기의 바닥까지 따라간다.
   * "가장 작은 τ"를 골라야 한 옥타브 낮게 읽는 오류(옥타브 오류)를 피한다.
   */
  private findFirstDip(): number | null {
    const { normalized, maxLag, threshold } = this
    let lag = 2
    while (lag <= maxLag) {
      if (normalized[lag] < threshold) {
        while (lag + 1 <= maxLag && normalized[lag + 1] < normalized[lag]) {
          lag += 1
        }
        return lag
      }
      lag += 1
    }
    return null
  }

  /**
   * 4단계 — 포물선 보간 (parabolic interpolation)
   *
   * 이웃한 세 점 d(τ−1), d(τ), d(τ+1)에 포물선을 맞춰 골짜기의 진짜 바닥(소수 τ)을 찾는다.
   * 꼭짓점: τ + (y₋ − y₊) / (2·(y₋ − 2y₀ + y₊))
   */
  private refineLag(lag: number): number {
    const left = this.difference[lag - 1]
    const center = this.difference[lag]
    const right = this.difference[lag + 1]
    const curvature = left - 2 * center + right
    if (!(curvature > 0)) {
      return lag
    }
    const offset = (left - right) / (2 * curvature)
    return lag + Math.min(1, Math.max(-1, offset))
  }
}
