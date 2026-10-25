import { audio } from '../audio/micInput'
import { peakMagnitude } from '../audio/wav'
import { playbackGain } from '../dsp/analysis'

export type CompareSide = 'A' | 'B'

/** 읽어 둔 녹음 하나 */
export interface LoadedRecording {
  readonly samples: Float32Array
  /** [Hz] */
  readonly sampleRate: number
  /** 들려줄 때 곱할 배율 (가장 큰 소리를 같은 크기로) */
  readonly gain: number
  /** [Hz] 목소리가 잡힌 높이들 (연습과 같은 YIN 분석) */
  readonly voiced: readonly number[]
  /** [s] */
  readonly duration: number
}

/**
 * 두 녹음 비교의 재생기 (iOS `ComparePlayer`): A·B 소리를 읽어 분석하고, 하나씩 또는 A → B로 이어 들려준다.
 * 두 녹음 모두 가장 큰 소리를 같은 크기로 맞춰 들려준다 (음량 차이는 비교되지 않는다).
 */
export class ComparePlayer {
  /** [s] A → B 이어 듣기에서 두 녹음 사이에 쉬는 시간 */
  static readonly gap = 0.7

  a: LoadedRecording | null = $state.raw(null)
  b: LoadedRecording | null = $state.raw(null)
  loading: CompareSide[] = $state([])
  /** 소리 파일을 읽지 못한 쪽 (숫자 기록만 비교한다) */
  failed: CompareSide[] = $state([])
  /** 지금 들리는 쪽 */
  playing: CompareSide | null = $state(null)
  /** [s] 지금 들리는 쪽이 끝나는 시각 (소리 시계) */
  endsAt = $state(0)

  /** 쪽마다 마지막으로 시작한 읽기. 고르는 녹음을 빨리 바꾸면 늦게 끝난 예전 읽기는 버린다 */
  #tokens: Record<CompareSide, number> = { A: 0, B: 0 }
  #gapTimer: ReturnType<typeof setTimeout> | null = null

  get(side: CompareSide): LoadedRecording | null {
    return side === 'A' ? this.a : this.b
  }

  #set(side: CompareSide, loaded: LoadedRecording | null): void {
    if (side === 'A') this.a = loaded
    else this.b = loaded
  }

  /** 녹음 소리를 읽어 분석한다 (`sound`가 null이면 파일이 없는 것). 고르는 녹음이 바뀔 때마다 부른다 */
  async load(side: CompareSide, sound: Promise<Blob | null>): Promise<void> {
    this.stop()
    const token = ++this.#tokens[side]
    this.#set(side, null)
    this.failed = this.failed.filter((s) => s !== side)
    this.loading = [...this.loading.filter((s) => s !== side), side]
    let loaded: LoadedRecording | null = null
    try {
      const blob = await sound
      if (blob !== null) {
        const analysis = await audio.analyzeFile(new File([blob], `${side}.wav`, { type: blob.type }))
        loaded = {
          samples: analysis.samples,
          sampleRate: analysis.sampleRate,
          gain: playbackGain(peakMagnitude(analysis.samples)),
          voiced: analysis.readings.flatMap((r) => (r.frequency === null ? [] : [r.frequency])),
          duration: analysis.samples.length / analysis.sampleRate,
        }
      }
    } catch {
      loaded = null
    }
    if (this.#tokens[side] !== token) return
    this.loading = this.loading.filter((s) => s !== side)
    if (loaded === null) this.failed = [...this.failed, side]
    this.#set(side, loaded)
  }

  /** 한쪽을 처음부터 들려준다 (버튼을 누른 그때 불러야 아이폰 사파리에서 소리가 난다) */
  play(side: CompareSide): void {
    this.stop()
    audio.prepare()
    this.#playNext([side])
  }

  /** A를 다 듣고 잠깐 쉰 뒤 B를 들려준다 */
  playBoth(): void {
    this.stop()
    audio.prepare()
    this.#playNext(['A', 'B'])
  }

  stop(): void {
    if (this.#gapTimer !== null) clearTimeout(this.#gapTimer)
    this.#gapTimer = null
    if (this.playing !== null) {
      this.playing = null
      audio.stopPlayback()
      void audio.rest()
    }
  }

  #playNext(queue: CompareSide[]): void {
    const [side, ...rest] = queue
    const loaded = side === undefined ? null : this.get(side)
    if (side === undefined || loaded === null) {
      this.stop()
      return
    }
    this.playing = side
    const start = audio.play(loaded.samples, loaded.sampleRate, loaded.gain, () => {
      if (this.playing !== side) return
      if (rest.length === 0) {
        this.stop()
        return
      }
      this.#gapTimer = setTimeout(() => {
        this.#gapTimer = null
        if (this.playing === side) this.#playNext(rest)
      }, ComparePlayer.gap * 1000)
    })
    this.endsAt = start + loaded.duration
  }
}
