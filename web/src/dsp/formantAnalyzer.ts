/** 포먼트 하나: 성도(목과 입안)가 울리는 주파수와 그 울림의 폭. */
export interface Formant {
  /** [Hz] 울림의 중심 주파수 */
  readonly frequency: number
  /** [Hz] 울림의 폭. 좁을수록 또렷한 울림이다. */
  readonly bandwidth: number
}

/** F1과 F2 */
export interface FormantEstimate {
  readonly f1: Formant
  readonly f2: Formant
}

/** 복소수. LPC 다항식의 근(극점)을 다룰 때만 쓴다. */
export interface Complex {
  readonly re: number
  readonly im: number
}

export function complex(re: number, im: number): Complex {
  return { re, im }
}

export function complexFromPolar(radius: number, angle: number): Complex {
  return { re: radius * Math.cos(angle), im: radius * Math.sin(angle) }
}

export function magnitude(z: Complex): number {
  return Math.hypot(z.re, z.im)
}

export function subtract(a: Complex, b: Complex): Complex {
  return { re: a.re - b.re, im: a.im - b.im }
}

function multiply(a: Complex, b: Complex): Complex {
  return { re: a.re * b.re - a.im * b.im, im: a.re * b.im + a.im * b.re }
}

function divide(a: Complex, b: Complex): Complex {
  const d = b.re * b.re + b.im * b.im
  return { re: (a.re * b.re + a.im * b.im) / d, im: (a.im * b.re - a.re * b.im) / d }
}

/**
 * 소리 조각 하나에서 포먼트(F1·F2)를 선형 예측(LPC)으로 잰다. iOS 앱 `Audio/FormantAnalyzer.swift`를 그대로 옮겼다.
 *
 * 순서: 12 kHz 안팎으로 표본 줄이기 → 고역 강조 → Hamming 창 → 자기상관
 *       → Levinson–Durbin(LPC 계수) → LPC 다항식의 근(Durand–Kerner)
 *       → 근의 각도 = 주파수, 반지름 = 대역폭 → 대역폭이 좁은 것 중 낮은 순서로 F1, F2.
 * 성별을 묻지 않으므로 최대 포먼트 주파수는 5500 Hz 하나로 둔다.
 */
export class FormantAnalyzer {
  /** [Hz] */
  static readonly maxFormantFrequency = 5500
  /** [Hz] 이보다 낮은 근은 포먼트가 아니라 성대 진동이나 잡음 쪽으로 본다 */
  static readonly minFormantFrequency = 90
  /** [Hz] 이보다 넓은 근은 또렷한 울림이 아니므로 F1·F2로 고르지 않는다 */
  static readonly maxBandwidth = 400
  /** 고역 강조 계수: y[n] = x[n] − 0.97·x[n−1] */
  static readonly preEmphasis = 0.97

  /** [Hz] 들어오는 소리의 표본화 주파수 */
  readonly inputSampleRate: number
  /** 몇 개마다 하나씩 남길지 (48 kHz → 4 → 12 kHz) */
  readonly decimationFactor: number
  /** [Hz] 표본을 줄인 뒤의 표본화 주파수 */
  readonly analysisRate: number
  /** LPC 차수. 기본은 표본화 주파수(kHz)와 같은 값(12 kHz → 12). */
  readonly order: number
  /** [s] 분석 창 길이. null이면 받은 조각 전체를 쓴다. */
  readonly windowDuration: number | null
  /** 표본을 줄이기 전에 거는 저역 통과 필터 (겹침 방지). iOS와 같이 단정밀도(Float)로 둔다. */
  private readonly lowPass: Float32Array

  /** `order`와 `windowDuration`은 검증할 때 여러 값을 비교할 때만 바꾼다. */
  constructor(sampleRate: number, order?: number, windowDuration?: number) {
    this.inputSampleRate = sampleRate
    const factor = Math.max(1, Math.floor(sampleRate / 11_000))
    this.decimationFactor = factor
    this.analysisRate = sampleRate / factor
    this.order = order ?? Math.trunc(this.analysisRate / 1000)
    this.windowDuration = windowDuration ?? null
    const cutoff = Math.min(FormantAnalyzer.maxFormantFrequency, 0.45 * this.analysisRate)
    this.lowPass = factor === 1 ? Float32Array.of(1) : FormantAnalyzer.lowPassFilter(cutoff, sampleRate, 63)
  }

  /** F1과 F2. 목소리가 없거나 또렷한 울림을 두 개 찾지 못하면 null. */
  estimate(frame: ArrayLike<number>): FormantEstimate | null {
    const candidates = this.formants(frame)?.filter((f) => f.bandwidth <= FormantAnalyzer.maxBandwidth)
    if (!candidates || candidates.length < 2) {
      return null
    }
    return { f1: candidates[0], f2: candidates[1] }
  }

  /** 포먼트 후보 전체 (주파수 오름차순, 대역폭으로 거르기 전). */
  formants(frame: ArrayLike<number>): Formant[] | null {
    const { decimationFactor, order, analysisRate } = this
    if (frame.length < this.lowPass.length + decimationFactor * (order + 2)) {
      return null
    }

    // 1. 표본 줄이기: 저역 통과 후 decimationFactor개마다 하나. 창 길이가 정해져 있으면 가운데만 쓴다.
    let decimated = FormantAnalyzer.downsample(frame, decimationFactor, this.lowPass)
    if (this.windowDuration !== null) {
      const length = Math.min(decimated.length, Math.trunc(this.windowDuration * analysisRate))
      const start = Math.trunc((decimated.length - length) / 2)
      decimated = decimated.slice(start, start + length)
    }
    if (decimated.length <= order + 1) {
      return null
    }

    // 2. 고역 강조, 3. Hamming 창 (LPC 계산은 정밀도를 위해 배정밀도로)
    const n = decimated.length
    const x = new Float64Array(n)
    x[0] = decimated[0]
    for (let i = 1; i < n; i++) {
      x[i] = decimated[i] - FormantAnalyzer.preEmphasis * decimated[i - 1]
    }
    const window = FormantAnalyzer.hammingWindow(n)
    for (let i = 0; i < n; i++) {
      x[i] *= window[i]
    }

    // 4. 자기상관 r[k] = Σ x[n]·x[n+k],  k = 0…order
    const r: number[] = []
    for (let k = 0; k <= order; k++) {
      let sum = 0
      for (let i = 0; i < n - k; i++) {
        sum += x[i] * x[i + k]
      }
      r.push(sum)
    }
    if (!(r[0] > 1e-12)) {
      return null
    }
    const a = FormantAnalyzer.levinsonDurbin(r, order)
    if (a === null) {
      return null
    }

    // 5. A(z) = 1 + a₁z⁻¹ + … + a_p z⁻ᵖ 의 근 = zᵖ + a₁zᵖ⁻¹ + … + a_p 의 근
    // 6. 켤레 근 한 쌍이 포먼트 하나: 각도 θ → 주파수 θ·fs/2π, 반지름 r → 대역폭 −ln(r)·fs/π
    const formants: Formant[] = []
    for (const z of FormantAnalyzer.polynomialRoots([1, ...a])) {
      if (!(z.im > 0)) continue
      const frequency = (Math.atan2(z.im, z.re) * analysisRate) / (2 * Math.PI)
      const bandwidth = (-Math.log(magnitude(z)) * analysisRate) / Math.PI
      if (frequency > FormantAnalyzer.minFormantFrequency && frequency < FormantAnalyzer.maxFormantFrequency) {
        formants.push({ frequency, bandwidth })
      }
    }
    return formants.sort((p, q) => p.frequency - q.frequency)
  }

  /**
   * 저역 통과 필터를 건 뒤 `factor`개마다 하나씩 남긴다 (iOS `vDSP.downsample`과 같은 식).
   *
   *     y[n] = Σ_{p=0}^{P−1} x[n·D + p] · h[p],   n = 0 … (N − P) / D
   */
  static downsample(x: ArrayLike<number>, factor: number, filter: ArrayLike<number>): Float32Array {
    const count = Math.floor((x.length - filter.length) / factor) + 1
    const y = new Float32Array(Math.max(count, 0))
    for (let i = 0; i < y.length; i++) {
      let sum = 0
      const offset = i * factor
      for (let p = 0; p < filter.length; p++) {
        sum += x[offset + p] * filter[p]
      }
      y[i] = sum
    }
    return y
  }

  /** Hamming 창 (iOS `vDSP.window(.hamming, isHalfWindow: false)`와 같은 식): w[n] = 0.54 − 0.46·cos(2πn/N) */
  static hammingWindow(count: number): Float64Array {
    const w = new Float64Array(count)
    for (let i = 0; i < count; i++) {
      w[i] = 0.54 - 0.46 * Math.cos((2 * Math.PI * i) / count)
    }
    return w
  }

  /**
   * 자기상관 r[0…p]로 예측 계수 a[1…p]를 구한다 (A(z) = 1 + Σ a_k z⁻ᵏ).
   * 토플리츠 행렬 연립방정식(정규 방정식)을 차수를 하나씩 올려 가며 O(p²)로 푼다.
   * 반사 계수 |k| ≥ 1이면 필터가 불안정하므로 null.
   */
  static levinsonDurbin(r: readonly number[], p: number): number[] | null {
    let a = new Array<number>(p + 1).fill(0)
    a[0] = 1
    let error = r[0]
    for (let i = 1; i <= p; i++) {
      let acc = r[i]
      for (let j = 1; j < i; j++) {
        acc += a[j] * r[i - j]
      }
      const k = -acc / error // 반사 계수
      if (!(Math.abs(k) < 1)) {
        return null
      }
      const previous = a
      a = previous.slice()
      for (let j = 1; j < i; j++) {
        a[j] = previous[j] + k * previous[i - j]
      }
      a[i] = k
      error *= 1 - k * k
    }
    return a.slice(1)
  }

  /**
   * 다항식 c₀zⁿ + c₁zⁿ⁻¹ + … + cₙ = 0 의 근 n개 (c₀ ≠ 0).
   * Durand–Kerner(바이어슈트라스) 반복: 모든 근을 동시에 z_i ← z_i − P(z_i) / Π_{j≠i}(z_i − z_j) 로 고쳐 간다.
   */
  static polynomialRoots(c: readonly number[]): Complex[] {
    const n = c.length - 1
    if (n <= 0 || c[0] === 0) {
      return []
    }
    const monic = c.map((value) => value / c[0])
    // 호너법으로 P(z) 계산 (맨 앞 계수는 1)
    const value = (z: Complex): Complex => {
      let result = complex(1, 0)
      for (let i = 1; i < monic.length; i++) {
        result = multiply(result, z)
        result = { re: result.re + monic[i], im: result.im }
      }
      return result
    }
    // 출발점: 반지름 0.9인 원 위에 고르게. 실수축 대칭을 피하려고 각도를 0.4 rad 비튼다.
    const roots: Complex[] = []
    for (let i = 0; i < n; i++) {
      roots.push(complexFromPolar(0.9, (2 * Math.PI * i) / n + 0.4))
    }
    for (let iteration = 0; iteration < 500; iteration++) {
      let largestStep = 0
      for (let i = 0; i < n; i++) {
        let denominator = complex(1, 0)
        for (let j = 0; j < n; j++) {
          if (j !== i) {
            denominator = multiply(denominator, subtract(roots[i], roots[j]))
          }
        }
        const step = divide(value(roots[i]), denominator)
        roots[i] = subtract(roots[i], step)
        largestStep = Math.max(largestStep, magnitude(step))
      }
      if (largestStep < 1e-12) break
    }
    return roots
  }

  /** Hamming 창을 씌운 sinc 저역 통과 필터. 직류 이득이 1이 되게 맞춘다. */
  static lowPassFilter(cutoff: number, sampleRate: number, taps: number): Float32Array {
    const fc = cutoff / sampleRate // 0 ~ 0.5
    const middle = (taps - 1) / 2
    const h: number[] = []
    for (let i = 0; i < taps; i++) {
      const k = i - middle
      const sinc = k === 0 ? 2 * fc : Math.sin(2 * Math.PI * fc * k) / (Math.PI * k)
      const window = 0.54 - 0.46 * Math.cos((2 * Math.PI * i) / (taps - 1))
      h.push(sinc * window)
    }
    const sum = h.reduce((total, value) => total + value, 0)
    return Float32Array.from(h, (value) => value / sum)
  }
}
