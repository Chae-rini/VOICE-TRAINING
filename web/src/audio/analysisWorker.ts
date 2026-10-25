import { analyzeSamples } from '../dsp/analysis'
import { StreamAnalyzer } from '../dsp/streamAnalyzer'
import { TakeRecorder } from '../practice/takeRecorder'
import type { ChunkMessage, WorkerCommand, WorkerMessage } from './messages'

/**
 * 분석 스레드 (Web Worker). 무거운 계산을 화면 스레드 밖에서 해서 그래프가 버벅이지 않게 한다.
 * - 녹음 중: 소리 받기에서 조각을 받아 높이·포먼트·크기를 재고(점을 화면으로), 최근 N초를 녹음 통에 남긴다.
 * - 듣는 중·숨 고르는 중: 들어오는 조각은 버린다 (스피커 소리가 다시 마이크로 들어가 섞이지 않게).
 * - 불러온 녹음: 처음부터 끝까지 분석해 점을 돌려준다.
 */
let analyzer: StreamAnalyzer | null = null
let recorder: TakeRecorder | null = null
let source: MessagePort | null = null
let sampleRate = 48_000
let recording = false

function send(message: WorkerMessage, transfer: Transferable[] = []) {
  self.postMessage(message, { transfer })
}

self.onmessage = (event: MessageEvent<WorkerCommand>) => {
  const command = event.data
  switch (command.type) {
    case 'start':
      source?.close()
      sampleRate = command.sampleRate
      analyzer = new StreamAnalyzer(sampleRate)
      source = command.port
      source.onmessage = (chunkEvent: MessageEvent<ChunkMessage>) => {
        if (!recording || analyzer === null) return
        const { samples, startFrame } = chunkEvent.data
        const time = startFrame / sampleRate
        recorder?.append(samples, time)
        const readings = analyzer.push(samples, time)
        if (readings.length > 0) send({ type: 'readings', readings })
      }
      break
    case 'begin':
      analyzer?.reset()
      recorder = new TakeRecorder(sampleRate, command.keepSeconds)
      recording = true
      break
    case 'finish': {
      recording = false
      const samples = recorder?.orderedSamples() ?? new Float32Array(0)
      send({ type: 'take', id: command.id, samples, startTime: recorder?.startTime ?? null }, [samples.buffer])
      recorder = null
      break
    }
    case 'analyze': {
      const readings = analyzeSamples(command.samples, command.sampleRate)
      send({ type: 'analysis', id: command.id, readings })
      break
    }
    case 'stop':
      recording = false
      source?.close()
      source = null
      analyzer = null
      recorder = null
      break
  }
}
