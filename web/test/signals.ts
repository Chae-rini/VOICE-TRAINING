/**
 * 테스트용 합성 신호. Tools/WebGolden/main.swift·VoicePracticeTests/SyntheticVowel.swift와 같은 식이라
 * 같은 숫자의 소리가 나온다 (단정밀도 Float로 반올림하는 것까지 Math.fround로 맞춘다).
 */

export function sine(frequency: number, sampleRate: number, count: number, amplitude = 0.5): Float32Array {
  return Float32Array.from({ length: count }, (_, n) => amplitude * Math.sin((2 * Math.PI * frequency * n) / sampleRate))
}

/** 배음 8개, k번째 배음의 진폭 0.3/k */
export function harmonic(f0: number, sampleRate: number, count: number): Float32Array {
  return Float32Array.from({ length: count }, (_, j) => {
    const t = j / sampleRate
    let sum = 0
    for (let k = 1; k <= 8; k++) {
      sum = sum + (0.3 / k) * Math.sin(2 * Math.PI * f0 * k * t)
    }
    return sum
  })
}

/** 높이가 `from`에서 `to`로 고르게 오르는 소리 (선형 처프) */
export function glide(from: number, to: number, seconds: number, sampleRate: number, amplitude: number): Float32Array {
  return Float32Array.from({ length: Math.trunc(sampleRate * seconds) }, (_, n) => {
    const t = n / sampleRate
    const phase = 2 * Math.PI * (from * t + ((to - from) * t * t) / (2 * seconds))
    return amplitude * Math.sin(phase)
  })
}

const MASK_64 = (1n << 64n) - 1n

/** SplitMix64 (64비트 정수 계산은 BigInt로). Swift 도구와 같은 수열을 만든다. */
export class SplitMix64 {
  private state: bigint

  constructor(seed: number | bigint) {
    this.state = BigInt(seed) & MASK_64
  }

  next(): bigint {
    this.state = (this.state + 0x9e3779b97f4a7c15n) & MASK_64
    let z = this.state
    z = ((z ^ (z >> 30n)) * 0xbf58476d1ce4e5b9n) & MASK_64
    z = ((z ^ (z >> 27n)) * 0x94d049bb133111ebn) & MASK_64
    return z ^ (z >> 31n)
  }

  /** 0 ≤ u < 1 (위 53비트) */
  uniform(): number {
    return Number(this.next() >> 11n) * 2 ** -53
  }
}

/** −amplitude ~ +amplitude 균등 분포 잡음. 같은 seed면 항상 같은 잡음이 나온다. */
export function noise(count: number, amplitude: number, seed: number): Float32Array {
  const generator = new SplitMix64(seed)
  return Float32Array.from({ length: count }, () => (generator.uniform() * 2 - 1) * amplitude)
}

/** 두 소리를 단정밀도로 더한다 (Swift `[Float]`끼리 더하기와 같게) */
export function add(a: Float32Array, b: Float32Array): Float32Array {
  return Float32Array.from(a, (value, i) => value + b[i])
}

/**
 * 시험용 합성 모음: 성대 펄스(F0) → 포먼트 공명기(F1~F4)를 거친 소리 (Klatt식 소스-필터 합성).
 * 모음별 포먼트 값은 모음 사이의 상대 배치를 흉내 낸 시험용 예시일 뿐, 특정 화자 집단의 평균이 아니다.
 */
export const SyntheticVowel = {
  shapes: [
    { name: '아', formants: [800, 1300, 2600, 3500] },
    { name: '어', formants: [600, 1000, 2600, 3500] },
    { name: '오', formants: [450, 800, 2600, 3500] },
    { name: '우', formants: [350, 900, 2500, 3500] },
    { name: '으', formants: [400, 1500, 2500, 3500] },
    { name: '이', formants: [300, 2300, 3000, 3700] },
    { name: '에', formants: [500, 1900, 2600, 3600] },
  ],

  /** [Hz] F1~F4의 대역폭 */
  bandwidths: [80, 100, 140, 180],

  /** `formants`를 가진 모음을 F0 `f0`로 `seconds`초 동안 낸 소리. */
  make(formants: readonly number[], f0: number, sampleRate: number, seconds: number): Float32Array {
    const count = Math.trunc(sampleRate * seconds)
    // 성대를 지나는 공기 흐름: 주기마다 Rosenberg 펄스 (열리는 데 주기의 40%, 닫히는 데 16%, 나머지는 닫힘)
    const period = sampleRate / f0 // [샘플]
    const opening = 0.4 * period
    const closing = 0.16 * period
    const source = Array.from({ length: count }, (_, n) => {
      const t = n % period
      if (t <= opening) return 0.5 * (1 - Math.cos((Math.PI * t) / opening))
      if (t <= opening + closing) return Math.cos((Math.PI * (t - opening)) / (2 * closing))
      return 0
    })
    // 입술에서 퍼져 나가며 높은 쪽이 세진다(약 +6 dB/옥타브): 1차 차분
    let y = source.map((value, n) => value - (n === 0 ? 0 : source[n - 1]))
    for (let i = 0; i < formants.length; i++) {
      y = SyntheticVowel.resonate(y, formants[i], SyntheticVowel.bandwidths[i], sampleRate)
    }
    const peak = y.reduce((max, value) => Math.max(max, Math.abs(value)), 0) || 1
    return Float32Array.from(y, (value) => (0.5 * value) / peak)
  },

  /** 2차 공명기: y[n] = A·x[n] + B·y[n−1] + C·y[n−2] */
  resonate(x: readonly number[], frequency: number, bandwidth: number, sampleRate: number): number[] {
    const t = 1 / sampleRate
    const c = -Math.exp(-2 * Math.PI * bandwidth * t)
    const b = 2 * Math.exp(-Math.PI * bandwidth * t) * Math.cos(2 * Math.PI * frequency * t)
    const a = 1 - b - c
    const y = new Array<number>(x.length).fill(0)
    for (let n = 0; n < x.length; n++) {
      y[n] = a * x[n] + b * (n >= 1 ? y[n - 1] : 0) + c * (n >= 2 ? y[n - 2] : 0)
    }
    return y
  },

  /** 소리의 0.2초 지점부터 hop마다 frameLength 길이로 자른 조각들 (첫 부분의 울림 시작은 건너뛴다) */
  frames(signal: Float32Array, sampleRate: number, frameLength = 2048, hop = 1024, count = 9): Float32Array[] {
    const start = Math.trunc(0.2 * sampleRate)
    const frames: Float32Array[] = []
    for (let i = 0; i < count; i++) {
      const from = start + i * hop
      if (from + frameLength <= signal.length) {
        frames.push(signal.slice(from, from + frameLength))
      }
    }
    return frames
  },
}
