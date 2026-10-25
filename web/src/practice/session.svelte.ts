import { MicError, startMicInput, type InputSource, type MicSession } from '../audio/micInput'
import type { ProcessingItem } from '../audio/processing'
import { GraphWindow } from '../dsp/graphWindow'
import { clockWindow, PitchHistory, type GraphClock, type PitchReading } from '../dsp/pitchHistory'
import { REST_REMINDER_SECONDS, restMessage } from '../graph/descriptions'
import { Baseline, type BaselineMeasurement } from '../model/practice'

export type Phase = 'idle' | 'starting' | 'live' | 'measuring'

/**
 * [높이] 화면의 지금 상태: 마이크를 켜고 끄기, 그래프 시계, 내 목소리 재기.
 * W3에서는 마이크를 켠 동안 그래프가 흐르기만 한다 (녹음 → 듣기 반복은 W4).
 */
class PracticeSession {
  phase: Phase = $state('idle')
  /** 그래프가 지금 무엇을 보여 주는지. 처음에는 녹음 없음 */
  clock: GraphClock = $state({ kind: 'frozen', window: null, at: null })
  errorMessage: string | null = $state(null)
  processing: ProcessingItem[] = $state([])
  sampleRate: number | null = $state(null)
  /** [s] 마이크를 켠 뒤 지난 시간 (화면 아래 표시용, 0.25초마다) */
  elapsed = $state(0)
  /** 오래 연습했을 때 목을 쉬어 가라는 안내. 다음에 켤 때까지 남겨 둔다 (원칙 4) */
  restMessage: string | null = $state(null)

  // 내 목소리 재기
  measurement: BaselineMeasurement | null = $state(null)
  /** [s] 재기가 끝날 때까지 남은 시간 */
  measuringRemaining = $state(0)

  /** 그래프에 그릴 점 (화면이 초당 수십 번 읽으므로 반응형으로 두지 않는다) */
  history = new PitchHistory()
  /** 재는 동안의 점 (재기 결과와 재기 화면의 지금 높이에만 쓴다. 그래프에는 섞지 않는다) */
  measuringHistory = new PitchHistory(Baseline.recordingSeconds + 2)

  #mic: MicSession | null = null
  #timer: ReturnType<typeof setInterval> | null = null
  #measureReadings: PitchReading[] = []
  /** 마이크가 없을 때 쓰는 시계 [s] */
  #idleClockOrigin = performance.now()

  /** 지금 시각 [s]: 마이크를 켠 동안은 소리 시계, 아니면 화면 시계 */
  now(): number {
    return this.#mic?.now() ?? (performance.now() - this.#idleClockOrigin) / 1000
  }

  get isRunning(): boolean {
    return this.phase !== 'idle'
  }

  /** 마이크를 켜고 그래프를 흐르게 한다. `duration`: 들려줄 길이 [s] = 그래프 가로축 */
  async startLive(source: InputSource, duration: number): Promise<void> {
    if (this.phase !== 'idle') return
    this.phase = 'starting'
    this.errorMessage = null
    this.restMessage = null
    const history = new PitchHistory(duration + 2)
    try {
      this.#mic = await startMicInput(source, (readings) => history.append(readings))
    } catch (error) {
      this.errorMessage = error instanceof MicError ? error.message : MicError.messages.other
      this.phase = 'idle'
      return
    }
    this.history = history
    this.processing = this.#mic.processing
    this.sampleRate = this.#mic.sampleRate
    const start = this.#mic.now()
    this.clock = { kind: 'live', start, duration, round: 1 }
    this.phase = 'live'
    let nextRest = REST_REMINDER_SECONDS
    this.#timer = setInterval(() => {
      this.elapsed = this.now() - start
      if (this.elapsed >= nextRest) {
        this.restMessage = restMessage(this.elapsed)
        nextRest += REST_REMINDER_SECONDS
      }
    }, 250)
  }

  /** 마이크를 끈다. 그래프는 끈 순간의 모습 그대로 멈춘다. */
  async stopLive(): Promise<void> {
    if (this.phase !== 'live' || this.#mic === null) return
    const now = this.#mic.now()
    this.clock = { kind: 'frozen', window: clockWindow(this.clock, now), at: now }
    await this.#release()
  }

  /** 내 목소리 재기: 10초 동안 마이크로 듣고 기준 목소리를 잰다. */
  async startMeasuring(source: InputSource): Promise<void> {
    if (this.phase !== 'idle') return
    this.phase = 'starting'
    this.errorMessage = null
    this.measurement = null
    this.#measureReadings = []
    const history = new PitchHistory(Baseline.recordingSeconds + 2)
    try {
      this.#mic = await startMicInput(source, (readings) => {
        history.append(readings)
        this.#measureReadings.push(...readings)
      })
    } catch (error) {
      this.errorMessage = error instanceof MicError ? error.message : MicError.messages.other
      this.phase = 'idle'
      return
    }
    this.measuringHistory = history
    this.phase = 'measuring'
    const endsAt = this.#mic.now() + Baseline.recordingSeconds
    this.measuringRemaining = Baseline.recordingSeconds
    this.#timer = setInterval(() => {
      this.measuringRemaining = Math.max(0, endsAt - this.now())
      if (this.measuringRemaining <= 0) void this.#finishMeasuring()
    }, 100)
  }

  async #finishMeasuring(): Promise<void> {
    if (this.phase !== 'measuring') return
    const readings = this.#measureReadings
    await this.#release()
    this.measurement = Baseline.measure(readings)
  }

  /** 재기를 그만두거나 결과를 지운다 (다시 재기, 닫기) */
  async cancelMeasuring(): Promise<void> {
    if (this.phase === 'measuring') await this.#release()
    this.measurement = null
  }

  async #release(): Promise<void> {
    if (this.#timer !== null) clearInterval(this.#timer)
    this.#timer = null
    const mic = this.#mic
    this.#mic = null
    this.phase = 'idle'
    this.elapsed = 0
    await mic?.stop()
  }

  /** 아직 녹음이 없을 때 보여 줄 빈 가로축 */
  idleWindow(endTime: number, duration: number): GraphWindow {
    return new GraphWindow(endTime - duration, duration)
  }
}

export const session = new PracticeSession()
