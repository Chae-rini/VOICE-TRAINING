import type { PitchReading } from '../dsp/pitchHistory'
import captureProcessorUrl from './captureProcessor?worker&url'
import { CAPTURE_PROCESSOR_NAME, type CaptureOptions, type WorkerCommand, type WorkerMessage } from './messages'
import { describeProcessing, MEASUREMENT_CONSTRAINTS, type ProcessingItem } from './processing'
import { mixToMono } from './wav'

/** 마이크를 켜지 못한 까닭 */
export type MicErrorKind = 'insecure' | 'unsupported' | 'denied' | 'notFound' | 'other'

export class MicError extends Error {
  constructor(
    readonly kind: MicErrorKind,
    cause?: unknown,
  ) {
    super(MicError.messages[kind], { cause })
  }

  static readonly messages: Record<MicErrorKind, string> = {
    insecure: '마이크는 https 주소나 이 컴퓨터(localhost)에서 연 페이지에서만 켜져요.',
    unsupported: '이 브라우저는 마이크 분석을 지원하지 않아요. 최신 Chrome·Safari·Firefox로 열어 주세요.',
    denied: '마이크를 쓸 수 없어요. 브라우저나 기기 설정에서 이 페이지의 마이크를 허용해 주세요.',
    notFound: '마이크를 찾지 못했어요. 마이크가 연결되어 있는지 확인해 주세요.',
    other: '마이크를 켜지 못했어요. 페이지를 새로 고친 뒤 다시 시도해 주세요.',
  }
}

/**
 * 무엇을 들을지: 마이크, 또는 (개발할 때만) 기본 높이 `testToneHz`의 합성음.
 * `formants` [Hz]를 주면 그 공명을 가진 모음처럼 배음 크기를 바꾼 합성음 ([모음] 화면 확인용).
 */
export type InputSource =
  | { readonly kind: 'mic' }
  | { readonly kind: 'testTone'; readonly testToneHz: number; readonly formants?: readonly number[] }

/**
 * [Hz] 개발용 합성 모음의 공명: 길이 17.5 cm의 고른 관(성도를 단순화한 모양)의 공명 c/4L·3c/4L·5c/4L·7c/4L.
 * 물리 모형으로 정한 시험 신호일 뿐, 어떤 화자 집단의 평균도 아니다 (원칙 3).
 */
export const TEST_VOWEL_FORMANTS: readonly number[] = [500, 1500, 2500, 3500]

/** 녹음 통에 남은 소리 */
export interface CapturedSound {
  readonly samples: Float32Array
  readonly sampleRate: number
  /** [s] 첫 샘플의 시각 (소리 시계) */
  readonly startTime: number
}

/** 불러온 녹음을 분석한 결과 */
export interface FileAnalysis {
  readonly samples: Float32Array
  readonly sampleRate: number
  readonly readings: PitchReading[]
  /** 5분이 넘어 앞부분만 불러왔는지 */
  readonly wasTruncated: boolean
}

interface OpenMic {
  readonly stream: MediaStream | null
  readonly worker: Worker
  readonly nodes: AudioNode[]
}

/**
 * 소리 장치: 마이크 → 소리 받기(AudioWorklet, 오디오 스레드) → 분석 스레드(Web Worker) → 화면, 그리고 다시 듣기 재생.
 * 소리 시계(AudioContext) 하나를 계속 써서 녹음·재생·그래프가 같은 시각을 본다.
 * 소리는 이 기기 안에서만 다루고 어디로도 보내지 않는다 (원칙 2).
 */
export class AudioEngine {
  #context: AudioContext | null = null
  #mic: OpenMic | null = null
  #player: AudioBufferSourceNode | null = null
  #nextId = 1
  #pending = new Map<number, (message: WorkerMessage) => void>()

  /**
   * 소리 시계를 만들거나 다시 깨운다. **버튼을 누른 그때(기다리기 전에)** 불러야 한다
   * (브라우저, 특히 아이폰 사파리는 사용자가 누른 직후에만 소리를 켜 준다).
   */
  prepare(): void {
    if (typeof AudioContext === 'undefined') return
    if (this.#context === null || this.#context.state === 'closed') {
      this.#context = new AudioContext({ latencyHint: 'interactive' })
    }
    void this.#context.resume()
  }

  /** [s] 지금 시각 (소리 시계). 아직 소리를 쓴 적이 없으면 화면 시계 */
  now(): number {
    return this.#context?.currentTime ?? performance.now() / 1000
  }

  get isMicOpen(): boolean {
    return this.#mic !== null
  }

  /** 마이크를 켜고 분석 스레드를 준비한다 (아직 녹음하지는 않는다). 자동 처리가 실제로 꺼졌는지 돌려준다. */
  async openMic(source: InputSource, onReadings: (readings: PitchReading[]) => void): Promise<ProcessingItem[]> {
    if (this.#mic !== null) return []
    if (source.kind === 'mic') {
      if (!window.isSecureContext) throw new MicError('insecure')
      if (!navigator.mediaDevices?.getUserMedia) throw new MicError('unsupported')
    }
    if (typeof AudioWorkletNode === 'undefined' || this.#context === null) throw new MicError('unsupported')
    const context = this.#context

    let stream: MediaStream | null = null
    if (source.kind === 'mic') {
      try {
        stream = await navigator.mediaDevices.getUserMedia({ audio: MEASUREMENT_CONSTRAINTS })
      } catch (error) {
        const name = error instanceof DOMException ? error.name : ''
        if (name === 'NotAllowedError' || name === 'SecurityError') throw new MicError('denied', error)
        if (name === 'NotFoundError' || name === 'OverconstrainedError') throw new MicError('notFound', error)
        throw new MicError('other', error)
      }
    }

    const worker = this.#makeWorker(onReadings)
    const nodes: AudioNode[] = []
    try {
      await context.resume()
      await context.audioWorklet.addModule(captureProcessorUrl)
      // 소리 받기 → 분석 스레드로 바로 가는 통로. 화면 스레드를 거치지 않아 화면이 바빠도 조각이 밀리지 않는다.
      const channel = new MessageChannel()
      worker.postMessage({ type: 'start', sampleRate: context.sampleRate, port: channel.port1 } satisfies WorkerCommand, [
        channel.port1,
      ])
      const capture = new AudioWorkletNode(context, CAPTURE_PROCESSOR_NAME, {
        numberOfInputs: 1,
        numberOfOutputs: 1,
        outputChannelCount: [1],
        processorOptions: { chunkSize: 1024 } satisfies CaptureOptions,
      })
      capture.port.postMessage({ port: channel.port2 }, [channel.port2])
      // 소리 받기가 계속 돌도록 출력까지 잇되, 음량 0으로 막아 스피커로는 나가지 않게 한다.
      const mute = context.createGain()
      mute.gain.value = 0
      capture.connect(mute).connect(context.destination)
      nodes.push(capture, mute)
      if (stream !== null) {
        const input = context.createMediaStreamSource(stream)
        input.connect(capture)
        nodes.push(input)
      } else if (source.kind === 'testTone') {
        nodes.push(...connectTestTone(context, source.testToneHz, capture, source.formants))
      }
    } catch (error) {
      stream?.getTracks().forEach((track) => track.stop())
      worker.terminate()
      nodes.forEach((node) => node.disconnect())
      throw error instanceof MicError ? error : new MicError('other', error)
    }

    this.#mic = { stream, worker, nodes }
    const track = stream?.getAudioTracks()[0]
    return track ? describeProcessing(track.getSettings()) : []
  }

  /** 녹음을 새로 시작한다: 최근 `keepSeconds`초만 남기고, 분석도 처음부터 */
  beginRecording(keepSeconds: number): void {
    this.#mic?.worker.postMessage({ type: 'begin', keepSeconds } satisfies WorkerCommand)
  }

  /** 녹음을 멈추고 남긴 소리를 받는다 (그 전에 분석한 점은 먼저 도착한다). 아무것도 녹음되지 않았으면 null. */
  async finishRecording(): Promise<CapturedSound | null> {
    const mic = this.#mic
    const context = this.#context
    if (mic === null || context === null) return null
    const id = this.#nextId++
    const reply = await this.#request(mic.worker, { type: 'finish', id }, id)
    if (reply.type !== 'take' || reply.samples.length === 0 || reply.startTime === null) return null
    return { samples: reply.samples, sampleRate: context.sampleRate, startTime: reply.startTime }
  }

  /** 마이크를 끈다 (브라우저의 마이크 표시도 사라진다). */
  closeMic(): void {
    const mic = this.#mic
    this.#mic = null
    if (mic === null) return
    mic.stream?.getTracks().forEach((track) => track.stop())
    mic.nodes.forEach((node) => {
      if (node instanceof OscillatorNode) node.stop()
      node.disconnect()
    })
    mic.worker.postMessage({ type: 'stop' } satisfies WorkerCommand)
    mic.worker.terminate()
  }

  /**
   * 원래 소리에 `gain`을 곱해 들려준다. 다 들으면 `onEnded`. 재생을 시작한 시각 [s, 소리 시계]을 돌려준다.
   * 일그러뜨리는 압축 없이 전체에 같은 배율만 곱한다 (목소리 판단을 흐리지 않게, iOS와 같다).
   */
  play(samples: Float32Array, sampleRate: number, gain: number, onEnded: () => void): number {
    this.stopPlayback()
    const context = this.#context
    if (context === null || samples.length === 0) {
      queueMicrotask(onEnded)
      return this.now()
    }
    const buffer = context.createBuffer(1, samples.length, sampleRate)
    const channel = buffer.getChannelData(0)
    // 개발 서버에서 주소 끝에 ?mute를 붙이면 소리 없이 재생한다 (테스트 음이 스피커로 나가지 않게, 흐름만 확인할 때).
    const volume = import.meta.env.DEV && new URLSearchParams(location.search).has('mute') ? 0 : 1
    for (let i = 0; i < samples.length; i++) channel[i] = samples[i] * gain * volume
    const player = context.createBufferSource()
    player.buffer = buffer
    player.connect(context.destination)
    player.onended = () => {
      if (this.#player === player) {
        this.#player = null
        onEnded()
      }
    }
    const start = context.currentTime
    player.start(start)
    this.#player = player
    return start
  }

  /** 재생을 멈춘다 (멈춘 재생의 `onEnded`는 부르지 않는다) */
  stopPlayback(): void {
    const player = this.#player
    this.#player = null
    if (player !== null) {
      try {
        player.stop()
      } catch {
        // 이미 끝난 재생
      }
      player.disconnect()
    }
  }

  /** 마이크도 재생도 없을 때 소리 시계를 쉬게 한다 (배터리) */
  async rest(): Promise<void> {
    if (this.#mic === null && this.#player === null && this.#context?.state === 'running') {
      await this.#context.suspend()
    }
  }

  /** 녹음 파일을 읽어(최대 5분) 모노로 바꾸고, 연습할 때와 같은 방식으로 분석 스레드에서 분석한다. */
  async analyzeFile(file: File): Promise<FileAnalysis> {
    const context = this.#context ?? new OfflineAudioContext(1, 1, 48_000)
    const decoded = await context.decodeAudioData(await file.arrayBuffer())
    const channels = Array.from({ length: decoded.numberOfChannels }, (_, i) => decoded.getChannelData(i))
    const { samples, wasTruncated } = mixToMono(channels, decoded.sampleRate)
    if (samples.length === 0) throw new Error('빈 파일')

    const worker = new Worker(new URL('./analysisWorker.ts', import.meta.url), { type: 'module' })
    try {
      const id = this.#nextId++
      // 분석에 넘기는 것은 사본이다 (원래 소리는 다시 듣기·저장에 쓴다).
      const copy = samples.slice()
      const reply = await this.#request(
        worker,
        { type: 'analyze', id, samples: copy, sampleRate: decoded.sampleRate },
        id,
        [copy.buffer],
      )
      if (reply.type !== 'analysis') throw new Error('분석 실패')
      return { samples, sampleRate: decoded.sampleRate, readings: reply.readings, wasTruncated }
    } finally {
      worker.terminate()
    }
  }

  #makeWorker(onReadings: (readings: PitchReading[]) => void): Worker {
    const worker = new Worker(new URL('./analysisWorker.ts', import.meta.url), { type: 'module' })
    worker.onmessage = (event: MessageEvent<WorkerMessage>) => {
      const message = event.data
      if (message.type === 'readings') onReadings(message.readings)
      else this.#pending.get(message.id)?.(message)
    }
    return worker
  }

  #request(worker: Worker, command: WorkerCommand, id: number, transfer: Transferable[] = []): Promise<WorkerMessage> {
    return new Promise((resolve, reject) => {
      const previous = worker.onmessage
      if (worker !== this.#mic?.worker) {
        // 파일 분석용 일꾼은 따로라 여기서 답을 받는다
        worker.onmessage = (event: MessageEvent<WorkerMessage>) => {
          if ('id' in event.data && event.data.id === id) resolve(event.data)
        }
      } else {
        this.#pending.set(id, (message) => {
          this.#pending.delete(id)
          resolve(message)
        })
      }
      worker.onerror = (event) => {
        worker.onmessage = previous
        reject(new Error(event.message))
      }
      worker.postMessage(command, transfer)
    })
  }
}

/**
 * 개발용 합성음: 배음 4개(진폭 1/k)를 섞은 소리. 마이크 없이 흐름 전체를 확인할 때 쓴다. 스피커로는 나가지 않는다.
 * `formants`를 주면 4 kHz까지의 배음을 쓰고, 배음마다 공명기(대역폭 100 Hz) 크기를 곱해 모음처럼 만든다.
 */
function connectTestTone(context: AudioContext, f0: number, destination: AudioNode, formants?: readonly number[]): AudioNode[] {
  const count = formants === undefined ? 4 : Math.floor(4000 / f0)
  // 2차 공명기의 크기: |H(f)| = F² / √((F² − f²)² + (B·f)²), 낮은 쪽에서 1
  const envelope = (f: number) =>
    (formants ?? []).reduce((product, F) => product * ((F * F) / Math.hypot(F * F - f * f, 100 * f)), 1)
  const amplitudes = Array.from({ length: count }, (_, i) => (formants === undefined ? 1 / (i + 1) : envelope(f0 * (i + 1))))
  const scale = formants === undefined ? 0.2 : 0.5 / amplitudes.reduce((sum, a) => sum + a, 0)
  const nodes: AudioNode[] = []
  amplitudes.forEach((amplitude, i) => {
    const oscillator = context.createOscillator()
    oscillator.frequency.value = f0 * (i + 1)
    const gain = context.createGain()
    gain.gain.value = scale * amplitude
    oscillator.connect(gain).connect(destination)
    oscillator.start()
    nodes.push(oscillator, gain)
  })
  return nodes
}

export const audio = new AudioEngine()
