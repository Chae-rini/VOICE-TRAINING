import type { PitchReading } from '../dsp/pitchHistory'
import captureProcessorUrl from './captureProcessor?worker&url'
import { CAPTURE_PROCESSOR_NAME, type CaptureOptions, type ReadingsMessage, type WorkerCommand } from './messages'
import { describeProcessing, MEASUREMENT_CONSTRAINTS, type ProcessingItem } from './processing'

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

/** 무엇을 들을지: 마이크, 또는 (개발할 때만) 기본 높이 `testToneHz`의 합성음 */
export type InputSource = { readonly kind: 'mic' } | { readonly kind: 'testTone'; readonly testToneHz: number }

export interface MicSession {
  /** [Hz] 소리의 표본화 주파수 (기기마다 44.1 kHz·48 kHz 등) */
  readonly sampleRate: number
  /** 자동 처리(자동 음량 조절 등)가 실제로 꺼졌는지. 테스트 음이면 빈 목록 */
  readonly processing: ProcessingItem[]
  /** [s] 지금 시각 (점의 시각과 같은 소리 시계) */
  now(): number
  stop(): Promise<void>
}

/**
 * 마이크 소리를 받아 분석 스레드에서 높이·포먼트·크기를 재고, 점이 나올 때마다 `onReadings`로 넘긴다.
 * 흐름: 마이크 → 소리 받기(AudioWorklet, 오디오 스레드) → 분석(Web Worker) → 화면.
 * 소리는 이 기기 안에서만 다루고 어디로도 보내지 않는다 (원칙 2). 버튼을 누른 뒤에 불러야 한다 (브라우저 규칙).
 */
export async function startMicInput(
  source: InputSource,
  onReadings: (readings: PitchReading[]) => void,
): Promise<MicSession> {
  if (source.kind === 'mic') {
    if (!window.isSecureContext) throw new MicError('insecure')
    if (!navigator.mediaDevices?.getUserMedia) throw new MicError('unsupported')
  }
  if (typeof AudioWorkletNode === 'undefined') throw new MicError('unsupported')

  // 소리 시계는 버튼을 누른 바로 그때 만든다 (아이폰 사파리는 사용자가 누른 직후에만 소리를 켜 준다).
  const context = new AudioContext({ latencyHint: 'interactive' })
  let stream: MediaStream | null = null
  if (source.kind === 'mic') {
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: MEASUREMENT_CONSTRAINTS })
    } catch (error) {
      await context.close()
      const name = error instanceof DOMException ? error.name : ''
      if (name === 'NotAllowedError' || name === 'SecurityError') throw new MicError('denied', error)
      if (name === 'NotFoundError' || name === 'OverconstrainedError') throw new MicError('notFound', error)
      throw new MicError('other', error)
    }
  }

  const worker = new Worker(new URL('./analysisWorker.ts', import.meta.url), { type: 'module' })
  const stopAll = async () => {
    stream?.getTracks().forEach((track) => track.stop())
    worker.postMessage({ type: 'stop' } satisfies WorkerCommand)
    worker.terminate()
    if (context.state !== 'closed') await context.close()
  }

  try {
    await context.resume()
    await context.audioWorklet.addModule(captureProcessorUrl)

    // 소리 받기 → 분석 스레드로 바로 가는 통로. 화면 스레드를 거치지 않아 화면이 바빠도 조각이 밀리지 않는다.
    const channel = new MessageChannel()
    worker.postMessage({ type: 'start', sampleRate: context.sampleRate, port: channel.port1 } satisfies WorkerCommand, [
      channel.port1,
    ])
    worker.onmessage = (event: MessageEvent<ReadingsMessage>) => {
      if (event.data.type === 'readings') onReadings(event.data.readings)
    }

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

    if (stream !== null) {
      context.createMediaStreamSource(stream).connect(capture)
    } else if (source.kind === 'testTone') {
      connectTestTone(context, source.testToneHz, capture)
    }
  } catch (error) {
    await stopAll()
    throw error instanceof MicError ? error : new MicError('other', error)
  }

  const track = stream?.getAudioTracks()[0]
  return {
    sampleRate: context.sampleRate,
    processing: track ? describeProcessing(track.getSettings()) : [],
    now: () => context.currentTime,
    stop: stopAll,
  }
}

/** 개발용 합성음: 배음 4개(진폭 1/k)를 섞은 소리. 마이크 없이 흐름 전체를 확인할 때 쓴다. 스피커로는 나가지 않는다. */
function connectTestTone(context: AudioContext, f0: number, destination: AudioNode): void {
  for (let k = 1; k <= 4; k++) {
    const oscillator = context.createOscillator()
    oscillator.frequency.value = f0 * k
    const gain = context.createGain()
    gain.gain.value = 0.2 / k
    oscillator.connect(gain).connect(destination)
    oscillator.start()
  }
}
