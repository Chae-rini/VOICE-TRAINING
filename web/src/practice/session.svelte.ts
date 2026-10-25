import { audio, MicError, type InputSource } from '../audio/micInput'
import type { ProcessingItem } from '../audio/processing'
import { peakMagnitude } from '../audio/wav'
import { playbackGain } from '../dsp/analysis'
import { GraphWindow } from '../dsp/graphWindow'
import { PitchHistory, type GraphClock, type PitchReading } from '../dsp/pitchHistory'
import { REST_REMINDER_SECONDS, restMessage } from '../graph/descriptions'
import { Baseline, type BaselineMeasurement } from '../model/practice'
import { COUNTDOWN_SECONDS, PracticeLoop, type LoopPhase } from './loop'
import { makeTake, takeDuration, takeEndTime, takeGraphWindow, takeHistory, type RecordedTake } from './take'

/**
 * [높이] 화면의 연습 흐름 (iOS `AudioInputManager`): 반복 루프(녹음 → 지금 들어보기 → 숨 고르기 → 다시 녹음),
 * 마지막 녹음 다시 듣기, 녹음 파일 불러오기, 내 목소리 재기. 단계 순서는 `PracticeLoop`가 정한다.
 */
class PracticeSession {
  /** 지금 단계 (화면이 보는 사본. 실제 순서는 #loop) */
  phase: LoopPhase = $state({ kind: 'idle' })
  /** 마이크를 켜는 중·녹음 파일을 분석하는 중·멈추는 중 (이때 누른 버튼은 무시한다) */
  busy: 'starting' | 'analyzing' | 'stopping' | null = $state(null)
  /** 그래프가 지금 무엇을 보여 주는지 */
  clock: GraphClock = $state({ kind: 'frozen', window: null, at: null })
  errorMessage: string | null = $state(null)
  /** 잠깐 보여 줄 안내 (예: 긴 파일은 앞부분만 불러왔다) */
  infoMessage: string | null = $state(null)
  /** 오래 연습했을 때 목을 쉬어 가라는 안내. 다음 연습이나 파일 불러오기 전까지 남겨 둔다 (원칙 4) */
  restMessage: string | null = $state(null)
  processing: ProcessingItem[] = $state([])
  /** 마지막 녹음 (방금 녹음 또는 불러온 파일). 요약 카드·다시 듣기·저장·공유가 이것만 쓴다 */
  lastTake: RecordedTake | null = $state.raw(null)
  /** [s] 녹음한 시간 (녹음 중) */
  elapsed = $state(0)
  /** [s] 듣기·숨 고르기·재기의 남은 시간 */
  remaining = $state(0)

  // 내 목소리 재기
  measurement: BaselineMeasurement | null = $state(null)

  /** 그래프에 그릴 점 (화면이 초당 수십 번 읽으므로 반응형으로 두지 않는다) */
  history = new PitchHistory()
  /** 재는 동안의 점 (재기 결과와 재기 화면의 지금 높이에만 쓴다. 그래프·마지막 녹음에는 섞지 않는다) */
  measuringHistory = new PitchHistory(Baseline.recordingSeconds + 2)

  #loop = new PracticeLoop()
  /** [s] 들려줄 길이 = 녹음 통에 남길 길이 = 그래프 가로축 */
  #keepSeconds = 60
  #measureReadings: PitchReading[] = []
  #ticker: ReturnType<typeof setInterval> | null = null
  #phaseTimer: ReturnType<typeof setTimeout> | null = null
  #phaseEndsAt = 0
  #recordingStartedAt = 0
  #restTimer: ReturnType<typeof setInterval> | null = null

  /** [s] 지금 시각 (소리 시계) */
  now(): number {
    return audio.now()
  }

  /** 녹음·듣기·숨 고르기·다시 듣기·재기 중이거나 마이크를 켜는 중·파일을 분석하는 중 */
  get isRunning(): boolean {
    return this.phase.kind !== 'idle' || this.busy !== null
  }

  /** 버튼을 누른 그때 소리를 준비한다 (녹음 파일 고르기 창을 열기 전에도 부른다). */
  prepareAudio(): void {
    audio.prepare()
  }

  // MARK: - 반복 루프

  /** 연습을 시작한다. 정지할 때까지 녹음 → (들어보기를 누르면) 듣기 → 다시 녹음을 이어 간다. */
  async start(source: InputSource, keepSeconds: number): Promise<void> {
    if (this.isRunning) return
    audio.prepare()
    this.#clearMessages()
    this.restMessage = null
    this.busy = 'starting'
    try {
      this.processing = await audio.openMic(source, (readings) => this.#receive(readings))
    } catch (error) {
      this.errorMessage = error instanceof MicError ? error.message : MicError.messages.other
      return
    } finally {
      this.busy = null
    }
    this.#keepSeconds = keepSeconds
    this.#loop.start()
    this.#syncPhase()
    this.#startRestReminders()
    this.#beginRecording()
  }

  /** 녹음 중에 누르면, 남겨 둔 최근 녹음(최대 N초)을 바로 들려준다. 다 들으면 자동으로 다시 녹음한다. */
  async listenNow(): Promise<void> {
    if (this.#loop.phase.kind !== 'recording') return
    this.#stopTicker()
    // 단계를 먼저 넘겨 두 번 눌러도 한 번만 듣게 한다 (그 사이 늦게 온 점은 iOS처럼 버린다).
    this.#loop.recordingFinished()
    this.#syncPhase()
    const take = await this.#keepTake()
    // 기다리는 사이 정지했을 수 있다 (TypeScript는 위의 확인 때문에 아직 녹음 중이라고 여겨서 다시 읽는다)
    if ((this.#loop.phase as LoopPhase).kind !== 'listening') return
    if (take !== null) this.#play(take)
    else this.#finishListening() // 녹음된 소리가 없으면 듣기를 건너뛴다
  }

  /** 듣는 중에 바로 다음 단계로 넘어간다. */
  skipListening(): void {
    if (this.#loop.phase.kind === 'listening') this.#finishListening()
  }

  /** 연습이 끝난 뒤 마지막 녹음을 다시 듣는다. */
  replayLastTake(): void {
    const take = this.lastTake
    if (this.isRunning || take === null) return
    audio.prepare()
    this.errorMessage = null
    this.history = takeHistory(take)
    this.#loop.startReplay()
    this.#syncPhase()
    this.#play(take)
  }

  /** 연습을 멈춘다. 녹음 도중이었다면 거기까지 녹음한 소리를 남겨 다시 들을 수 있게 한다. */
  async stop(): Promise<void> {
    const phase = this.#loop.phase.kind
    if (phase === 'idle' || this.busy === 'stopping') return
    this.busy = 'stopping'
    this.#clearPhaseTimer()
    this.#stopTicker()
    this.#stopRestReminders()
    audio.stopPlayback()
    this.#loop.stop()
    this.#syncPhase()
    try {
      if (phase === 'recording') await this.#keepTake()
      if (phase === 'measuring') this.measurement = null
      this.clock = this.#lastTakeClock()
      audio.closeMic()
      await audio.rest()
    } finally {
      this.busy = null
    }
  }

  #beginRecording(): void {
    // 그래프는 왼쪽 끝이 비지 않게 여유 2초를 두고 그린다. 이 여유는 수치에 쓰지 않는다 (녹음 묶음만 쓴다).
    this.history = new PitchHistory(this.#keepSeconds + 2)
    audio.beginRecording(this.#keepSeconds)
    const round = this.#loop.phase.kind === 'recording' ? this.#loop.phase.round : null
    const start = audio.now()
    this.clock = { kind: 'live', start, duration: this.#keepSeconds, round }
    this.#recordingStartedAt = start
    this.elapsed = 0
    this.#startTicker()
  }

  /** 지금까지 녹음한 소리를 "마지막 녹음"으로 남긴다. 소리 구간의 점만 묶음에 넣는다. */
  async #keepTake(): Promise<RecordedTake | null> {
    const clock = this.clock
    const sound = await audio.finishRecording()
    if (sound === null) return null
    const take = makeTake({
      samples: sound.samples,
      sampleRate: sound.sampleRate,
      startTime: sound.startTime,
      playbackGain: playbackGain(peakMagnitude(sound.samples)),
      recordedAt: new Date(),
      title: '방금 녹음',
      readings: this.history.readings,
      graphDuration: this.#keepSeconds,
      recordingStart: clock.kind === 'live' ? clock.start : null,
      round: clock.kind === 'live' ? clock.round : null,
    })
    this.lastTake = take
    this.history = takeHistory(take)
    this.clock = this.#lastTakeClock()
    return take
  }

  #play(take: RecordedTake): void {
    const playbackStart = audio.play(take.samples, take.sampleRate, take.playbackGain, () => this.#finishListening())
    // 녹음 구간 전체를 보이고 재생 위치만 움직인다.
    this.clock = { kind: 'replay', window: takeGraphWindow(take), takeStart: take.startTime, playbackStart }
    this.#phaseEndsAt = audio.now() + takeDuration(take)
    this.#startTicker()
  }

  #finishListening(): void {
    audio.stopPlayback()
    this.#stopTicker()
    this.clock = this.#lastTakeClock()
    this.#loop.listeningFinished()
    this.#syncPhase()
    if (this.#loop.phase.kind === 'countdown') {
      this.#phaseEndsAt = audio.now() + COUNTDOWN_SECONDS
      this.#startTicker()
      this.#phaseTimer = setTimeout(() => {
        this.#phaseTimer = null
        this.#loop.countdownFinished()
        this.#syncPhase()
        this.#beginRecording()
      }, COUNTDOWN_SECONDS * 1000)
    } else {
      void audio.rest() // 마지막 녹음 다시 듣기가 끝남
    }
  }

  // MARK: - 녹음 파일

  /** 녹음 파일(음성 메모 등)을 불러와 분석한 뒤, 곧바로 재생하며 곡선을 보여 준다. 파일은 이 기기 안에서 읽기만 한다. */
  async importFile(file: File): Promise<void> {
    if (this.isRunning) return
    this.#clearMessages()
    this.restMessage = null
    this.busy = 'analyzing'
    try {
      const analysis = await audio.analyzeFile(file)
      this.lastTake = makeTake({
        samples: analysis.samples,
        sampleRate: analysis.sampleRate,
        startTime: 0,
        playbackGain: playbackGain(peakMagnitude(analysis.samples)),
        recordedAt: new Date(),
        title: file.name.replace(/\.[^.]+$/, '') || '불러온 녹음',
        readings: analysis.readings,
        graphDuration: 0,
        recordingStart: null,
        round: null,
      })
      if (analysis.wasTruncated) this.infoMessage = '5분이 넘는 녹음이라 앞 5분만 불러왔어요.'
    } catch {
      this.errorMessage = '이 파일을 읽지 못했어요. 녹음(오디오) 파일인지 확인해 주세요.'
      return
    } finally {
      this.busy = null
    }
    this.replayLastTake()
  }

  // MARK: - 내 목소리 재기

  /** 마이크로 10초 녹음해 기준 목소리를 잰다 (연습과 같은 분석). 결과는 `measurement`. 마지막 녹음은 바꾸지 않는다. */
  async startMeasuring(source: InputSource): Promise<void> {
    if (this.isRunning) return
    audio.prepare()
    this.errorMessage = null
    this.measurement = null
    this.busy = 'starting'
    try {
      await audio.openMic(source, (readings) => this.#receive(readings))
    } catch (error) {
      this.errorMessage = error instanceof MicError ? error.message : MicError.messages.other
      return
    } finally {
      this.busy = null
    }
    this.#measureReadings = []
    this.measuringHistory = new PitchHistory(Baseline.recordingSeconds + 2)
    this.#loop.startMeasuring()
    this.#syncPhase()
    audio.beginRecording(Baseline.recordingSeconds)
    this.#phaseEndsAt = audio.now() + Baseline.recordingSeconds
    this.#startTicker()
    this.#phaseTimer = setTimeout(() => void this.#finishMeasuring(), Baseline.recordingSeconds * 1000)
  }

  async #finishMeasuring(): Promise<void> {
    this.#phaseTimer = null
    if (this.#loop.phase.kind !== 'measuring') return
    await audio.finishRecording() // 잰 소리는 버린다 (점만 쓴다)
    this.#stopTicker()
    this.#loop.stop()
    this.#syncPhase()
    audio.closeMic()
    void audio.rest()
    this.measurement = Baseline.measure(this.#measureReadings)
  }

  /** 녹음 파일(음성 메모 등)로 기준 목소리를 잰다. */
  async measureFromFile(file: File): Promise<void> {
    if (this.isRunning) return
    this.errorMessage = null
    this.measurement = null
    this.busy = 'analyzing'
    try {
      this.measurement = Baseline.measure((await audio.analyzeFile(file)).readings)
    } catch {
      this.errorMessage = '이 파일을 읽지 못했어요. 녹음(오디오) 파일인지 확인해 주세요.'
    } finally {
      this.busy = null
    }
  }

  /** 재기를 그만두거나 결과를 지운다 (다시 재기, 닫기) */
  async cancelMeasuring(): Promise<void> {
    if (this.#loop.phase.kind === 'measuring') await this.stop()
    this.measurement = null
    this.errorMessage = null
  }

  // MARK: - 안쪽

  #receive(readings: PitchReading[]): void {
    // 녹음·재기 단계가 끝난 뒤에 늦게 도착한 결과는 버린다.
    switch (this.#loop.phase.kind) {
      case 'recording':
        this.history.append(readings)
        break
      case 'measuring':
        this.measuringHistory.append(readings)
        this.#measureReadings.push(...readings)
        break
    }
  }

  /** 멈춘 화면의 그래프: 마지막 녹음의 구간을 그대로 보여 준다 (녹음이 없으면 빈 그래프) */
  #lastTakeClock(): GraphClock {
    const take = this.lastTake
    return take === null
      ? { kind: 'frozen', window: null, at: null }
      : { kind: 'frozen', window: takeGraphWindow(take), at: takeEndTime(take) }
  }

  #syncPhase(): void {
    this.phase = this.#loop.phase
  }

  #clearMessages(): void {
    this.errorMessage = null
    this.infoMessage = null
  }

  #startTicker(): void {
    this.#stopTicker()
    const tick = () => {
      const now = audio.now()
      if (this.#loop.phase.kind === 'recording') this.elapsed = now - this.#recordingStartedAt
      else this.remaining = Math.max(0, this.#phaseEndsAt - now)
    }
    tick()
    this.#ticker = setInterval(tick, 200)
  }

  #stopTicker(): void {
    if (this.#ticker !== null) clearInterval(this.#ticker)
    this.#ticker = null
  }

  #clearPhaseTimer(): void {
    if (this.#phaseTimer !== null) clearTimeout(this.#phaseTimer)
    this.#phaseTimer = null
  }

  /** 정지할 때까지 쉬지 않고 연습하면, 15분마다 목을 쉬어 가라고 알린다 (연습은 멈추지 않는다). */
  #startRestReminders(): void {
    this.#stopRestReminders()
    let elapsed = 0
    this.#restTimer = setInterval(() => {
      elapsed += REST_REMINDER_SECONDS
      this.restMessage = restMessage(elapsed)
    }, REST_REMINDER_SECONDS * 1000)
  }

  #stopRestReminders(): void {
    if (this.#restTimer !== null) clearInterval(this.#restTimer)
    this.#restTimer = null
  }

  /** 아직 녹음이 없을 때 보여 줄 빈 가로축 */
  idleWindow(endTime: number, duration: number): GraphWindow {
    return new GraphWindow(endTime - duration, duration)
  }
}

export const session = new PracticeSession()
