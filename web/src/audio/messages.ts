import type { PitchReading } from '../dsp/pitchHistory'

/** 소리 받기(AudioWorklet) → 분석 스레드(Web Worker): 소리 조각 하나 */
export interface ChunkMessage {
  readonly samples: Float32Array
  /** 조각 첫 샘플의 위치 [샘플, AudioContext 시계]. 시각 [s] = startFrame / sampleRate */
  readonly startFrame: number
}

/** 화면 → 분석 스레드 */
export type WorkerCommand =
  /** 분석을 시작한다. `port`로 소리 받기에서 조각이 바로 들어온다 (화면 스레드를 거치지 않는다). */
  | { readonly type: 'start'; readonly sampleRate: number; readonly port: MessagePort }
  | { readonly type: 'stop' }

/** 분석 스레드 → 화면 */
export interface ReadingsMessage {
  readonly type: 'readings'
  readonly readings: PitchReading[]
}

/** 소리 받기에 처음 넘기는 설정 */
export interface CaptureOptions {
  /** [샘플] 이만큼 모아서 분석 스레드로 보낸다 */
  readonly chunkSize: number
}

export const CAPTURE_PROCESSOR_NAME = 'ullim-capture'
