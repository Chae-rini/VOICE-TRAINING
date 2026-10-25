import { StreamAnalyzer } from '../dsp/streamAnalyzer'
import type { ChunkMessage, ReadingsMessage, WorkerCommand } from './messages'

/**
 * 분석 스레드 (Web Worker). 소리 받기에서 조각을 받아 높이·포먼트·크기를 재고, 점을 화면으로 보낸다.
 * 분석(창 하나에 1~2 ms)을 화면 스레드 밖에서 해서 그래프가 버벅이지 않게 한다.
 */
let analyzer: StreamAnalyzer | null = null
let source: MessagePort | null = null

self.onmessage = (event: MessageEvent<WorkerCommand>) => {
  const command = event.data
  switch (command.type) {
    case 'start': {
      source?.close()
      const sampleRate = command.sampleRate
      const current = new StreamAnalyzer(sampleRate)
      analyzer = current
      source = command.port
      source.onmessage = (chunkEvent: MessageEvent<ChunkMessage>) => {
        const { samples, startFrame } = chunkEvent.data
        const readings = current.push(samples, startFrame / sampleRate)
        if (readings.length > 0) {
          const message: ReadingsMessage = { type: 'readings', readings }
          self.postMessage(message)
        }
      }
      break
    }
    case 'stop':
      source?.close()
      source = null
      analyzer = null
      break
  }
}
