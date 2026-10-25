/// <reference path="./worklet-globals.d.ts" />
import { CAPTURE_PROCESSOR_NAME, type CaptureOptions, type ChunkMessage } from './messages'

/**
 * 소리 받기 (오디오 스레드, AudioWorklet). iOS의 입력 탭에 해당한다.
 * 브라우저는 128샘플씩 주므로 `chunkSize`만큼 모아 분석 스레드로 바로 보낸다. 여기서는 분석하지 않는다
 * (오디오 스레드가 늦으면 소리가 끊기므로 가볍게 둔다). 첫 채널만 쓴다 (iOS 연습 녹음과 같다).
 */
class CaptureProcessor extends AudioWorkletProcessor {
  private target: MessagePort | null = null
  private readonly chunkSize: number
  private chunk: Float32Array
  private filled = 0
  private chunkStartFrame = 0

  constructor(options: AudioWorkletNodeOptions) {
    super(options)
    this.chunkSize = (options.processorOptions as CaptureOptions | undefined)?.chunkSize ?? 1024
    this.chunk = new Float32Array(this.chunkSize)
    // 화면 스레드가 분석 스레드로 가는 통로(MessagePort)를 넘겨준다.
    this.port.onmessage = (event: MessageEvent<{ port: MessagePort }>) => {
      this.target = event.data.port
    }
  }

  process(inputs: Float32Array[][]): boolean {
    const channel = inputs[0]?.[0]
    if (channel === undefined || this.target === null) {
      return true
    }
    for (let i = 0; i < channel.length; i++) {
      if (this.filled === 0) {
        this.chunkStartFrame = currentFrame + i
      }
      this.chunk[this.filled++] = channel[i]
      if (this.filled === this.chunkSize) {
        const message: ChunkMessage = { samples: this.chunk, startFrame: this.chunkStartFrame }
        // 복사하지 않고 넘긴다 (넘긴 뒤에는 새 통을 쓴다)
        this.target.postMessage(message, [this.chunk.buffer])
        this.chunk = new Float32Array(this.chunkSize)
        this.filled = 0
      }
    }
    return true
  }
}

registerProcessor(CAPTURE_PROCESSOR_NAME, CaptureProcessor)
