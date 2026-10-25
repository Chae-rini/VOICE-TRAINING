import type { PitchReading } from '../dsp/pitchHistory'

/** 소리 받기(AudioWorklet) → 분석 스레드(Web Worker): 소리 조각 하나 */
export interface ChunkMessage {
  readonly samples: Float32Array
  /** 조각 첫 샘플의 위치 [샘플, AudioContext 시계]. 시각 [s] = startFrame / sampleRate */
  readonly startFrame: number
}

/** 화면 → 분석 스레드 */
export type WorkerCommand =
  /** 마이크 조각을 받을 준비. `port`로 소리 받기에서 조각이 바로 들어온다 (화면 스레드를 거치지 않는다). */
  | { readonly type: 'start'; readonly sampleRate: number; readonly port: MessagePort }
  /** 녹음을 새로 시작한다: 최근 `keepSeconds`초만 남기는 녹음 통을 비우고 분석도 처음부터 */
  | { readonly type: 'begin'; readonly keepSeconds: number }
  /** 녹음을 멈추고 남긴 소리를 돌려 달라 (듣는 동안 들어오는 소리는 분석하지 않는다) */
  | { readonly type: 'finish'; readonly id: number }
  /** 불러온 녹음 전체를 분석해 달라 (화면이 멈추지 않게 여기서 한다) */
  | { readonly type: 'analyze'; readonly id: number; readonly samples: Float32Array; readonly sampleRate: number }
  | { readonly type: 'stop' }

/** 분석 스레드 → 화면 */
export type WorkerMessage =
  | { readonly type: 'readings'; readonly readings: PitchReading[] }
  /** 녹음 통에 남은 소리. 아무것도 녹음되지 않았으면 samples가 비어 있다 */
  | { readonly type: 'take'; readonly id: number; readonly samples: Float32Array; readonly startTime: number | null }
  | { readonly type: 'analysis'; readonly id: number; readonly readings: PitchReading[] }

/** 소리 받기에 처음 넘기는 설정 */
export interface CaptureOptions {
  /** [샘플] 이만큼 모아서 분석 스레드로 보낸다 */
  readonly chunkSize: number
}

export const CAPTURE_PROCESSOR_NAME = 'ullim-capture'
