// AudioWorklet 안에서만 있는 이름들. TypeScript 기본 타입(lib.dom)에 없어서 쓰는 만큼만 적는다.
// https://developer.mozilla.org/en-US/docs/Web/API/AudioWorkletGlobalScope

declare const currentFrame: number
declare const sampleRate: number

declare abstract class AudioWorkletProcessor {
  readonly port: MessagePort
  constructor(options?: AudioWorkletNodeOptions)
  abstract process(
    inputs: Float32Array[][],
    outputs: Float32Array[][],
    parameters: Record<string, Float32Array>,
  ): boolean
}

declare function registerProcessor(
  name: string,
  processorCtor: new (options: AudioWorkletNodeOptions) => AudioWorkletProcessor,
): void
