import { describe, expect, it } from 'vitest'
import { encodeWav, exportFileName, mixToMono, peakMagnitude } from '../src/audio/wav'
import { playbackGain, PLAYBACK_PEAK } from '../src/dsp/analysis'
import { GraphWindow } from '../src/dsp/graphWindow'
import { clockEndTime, clockWindow, type GraphClock } from '../src/dsp/pitchHistory'
import { range } from '../src/dsp/range'
import { PracticeLoop } from '../src/practice/loop'
import { takeWavFile } from '../src/practice/sharing'
import { makeTake, takeDuration, takeEndTime, takeGraphWindow, takeHistory, takeSummary } from '../src/practice/take'
import { TakeRecorder } from '../src/practice/takeRecorder'

// iOS VoicePracticeTests/PracticeLoopTests.swift (PracticeLoopTests·TakeRecorderTests)를 옮겼다.
describe('PracticeLoop (연습 순서)', () => {
  it('녹음 → 듣기 → 숨 고르기 → 다시 녹음으로 이어지고, 회차가 하나씩 늘어난다', () => {
    const loop = new PracticeLoop()
    loop.start()
    expect(loop.phase).toEqual({ kind: 'recording', round: 1 })
    loop.recordingFinished()
    expect(loop.phase).toEqual({ kind: 'listening', round: 1 })
    loop.listeningFinished()
    expect(loop.phase).toEqual({ kind: 'countdown', nextRound: 2 })
    loop.countdownFinished()
    expect(loop.phase).toEqual({ kind: 'recording', round: 2 })
  })

  it('횟수 제한 없이 정지할 때까지 계속된다', () => {
    const loop = new PracticeLoop()
    loop.start()
    for (let i = 0; i < 20; i++) {
      loop.recordingFinished()
      loop.listeningFinished()
      loop.countdownFinished()
    }
    expect(loop.phase).toEqual({ kind: 'recording', round: 21 })
    loop.stop()
    expect(loop.isActive).toBe(false)
  })

  it('늦게 도착한 신호는 무시한다 (예: 듣는 중에 ‘녹음 끝’)', () => {
    const loop = new PracticeLoop()
    loop.start()
    loop.recordingFinished()
    loop.recordingFinished()
    loop.countdownFinished()
    expect(loop.phase).toEqual({ kind: 'listening', round: 1 })
  })

  it('마지막 녹음 다시 듣기는 연습 중이 아닐 때만 되고, 끝나면 처음 상태로 돌아간다', () => {
    const loop = new PracticeLoop()
    loop.start()
    loop.startReplay()
    expect(loop.phase).toEqual({ kind: 'recording', round: 1 }) // 연습 중에는 무시
    loop.stop()
    loop.startReplay()
    expect(loop.phase).toEqual({ kind: 'replaying' })
    loop.listeningFinished()
    expect(loop.phase).toEqual({ kind: 'idle' })
  })

  it('내 목소리 재기는 연습 중이 아닐 때만 시작되고, 다른 신호는 무시한다', () => {
    const loop = new PracticeLoop()
    loop.startMeasuring()
    loop.recordingFinished()
    loop.listeningFinished()
    loop.countdownFinished()
    expect(loop.phase).toEqual({ kind: 'measuring' })
    loop.stop()
    loop.start()
    loop.startMeasuring()
    expect(loop.phase).toEqual({ kind: 'recording', round: 1 })
  })
})

describe('TakeRecorder (최근 N초 녹음 통)', () => {
  it('모은 소리와 첫 샘플의 시각을 기억한다', () => {
    const recorder = new TakeRecorder(48_000, 1)
    recorder.append(Float32Array.of(0.1, 0.2, 0.3), 5)
    recorder.append(Float32Array.of(0.4), 5 + 3 / 48_000)
    expect(recorder.startTime).toBeCloseTo(5, 9)
    expect(Array.from(recorder.orderedSamples())).toEqual([0.1, 0.2, 0.3, 0.4].map(Math.fround))
    expect(Math.abs(playbackGain(peakMagnitude(recorder.orderedSamples())) - PLAYBACK_PEAK / 0.4)).toBeLessThan(1e-4)
  })

  it('보관 길이를 넘으면 오래된 소리부터 버리고 최근 소리만 순서대로 남긴다', () => {
    const recorder = new TakeRecorder(10, 1) // 최근 10샘플
    recorder.append(Float32Array.from({ length: 8 }, (_, i) => i), 0)
    recorder.append(Float32Array.from({ length: 8 }, (_, i) => 8 + i), 0.8)
    expect(recorder.sampleCount).toBe(10)
    expect(recorder.startTime).toBeCloseTo(0.6, 9) // 1.6초에 끝난 소리의 최근 1초
    expect(Array.from(recorder.orderedSamples())).toEqual([6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
  })

  it('조각 하나가 보관 길이보다 길면 그 끝부분만 남긴다', () => {
    const recorder = new TakeRecorder(10, 1)
    recorder.append(Float32Array.from({ length: 25 }, (_, i) => i), 0)
    expect(recorder.sampleCount).toBe(10)
    expect(recorder.startTime).toBeCloseTo(1.5, 9)
    expect(Array.from(recorder.orderedSamples())).toEqual([15, 16, 17, 18, 19, 20, 21, 22, 23, 24])
  })

  it('아무것도 녹음하지 않았으면 소리도 시각도 없다', () => {
    const recorder = new TakeRecorder(48_000, 1)
    expect(recorder.orderedSamples()).toHaveLength(0)
    expect(recorder.startTime).toBeNull()
  })
})

describe('RecordedTake (녹음 묶음)', () => {
  /** 0.02초 간격, 200 Hz */
  const readings = Array.from({ length: 1250 }, (_, i) => ({ time: 100 + i * 0.02, frequency: 200 }))

  it('흐르는 중에 보인 구간 = 남긴 소리 = 요약 구간 (100초에 시작해 25초 녹음, 들려줄 길이 10초)', () => {
    const recorder = new TakeRecorder(1000, 10)
    recorder.append(new Float32Array(25_000).fill(0.1), 100)
    const live: GraphClock = { kind: 'live', start: 100, duration: 10, round: 1 }
    const window = clockWindow(live, 125)!
    expect(recorder.startTime).toBeCloseTo(window.start, 6)

    const take = makeTake({
      samples: recorder.orderedSamples(),
      sampleRate: 1000,
      startTime: recorder.startTime!,
      playbackGain: 1,
      recordedAt: new Date(),
      title: '방금 녹음',
      readings,
      graphDuration: 10,
      recordingStart: 100,
      round: 1,
    })
    expect(takeGraphWindow(take).start).toBeCloseTo(window.start, 6)
    expect(takeGraphWindow(take).duration).toBeCloseTo(10, 6)
    expect(take.readings.every((r) => r.time >= window.start - 1e-6 && r.time <= window.end + 1e-6)).toBe(true)
    // 요약은 소리 구간(최근 10초)의 점만: 0.02초 × 점 개수 ≈ 10초
    expect(takeSummary(take, range(180, 220))!.voicedSeconds).toBeCloseTo(10, 0)
    expect(takeHistory(take).readings).toHaveLength(take.readings.length)
  })

  it('녹음이 들려줄 길이보다 짧으면 왼쪽이 비고, 불러온 파일은 파일 길이만큼', () => {
    const short = makeTake({
      samples: new Float32Array(4000),
      sampleRate: 1000,
      startTime: 50,
      playbackGain: 1,
      recordedAt: new Date(),
      title: '방금 녹음',
      readings: [],
      graphDuration: 60,
      recordingStart: 50,
      round: null,
    })
    expect(takeDuration(short)).toBe(4)
    expect(takeEndTime(short)).toBe(54)
    expect(takeGraphWindow(short)).toEqual(new GraphWindow(-6, 60, 50, null))

    const imported = makeTake({
      samples: new Float32Array(3000),
      sampleRate: 1000,
      startTime: 0,
      playbackGain: 1,
      recordedAt: new Date(),
      title: '파일',
      readings: [],
      graphDuration: 0,
      recordingStart: null,
      round: null,
    })
    expect(takeGraphWindow(imported)).toEqual(new GraphWindow(0, 3, null, null))
  })

  it('다시 듣기 중 재생 위치는 녹음 첫 소리 시각 + 재생된 시간이고, 가로축은 녹음 구간 그대로다', () => {
    const window = new GraphWindow(52, 60, 100) // 12초 녹음, 오른쪽 끝 = 녹음 끝(112초)
    const clock: GraphClock = { kind: 'replay', window, takeStart: 100, playbackStart: 500 }
    expect(clockEndTime(clock, 503)).toBe(103)
    expect(clockWindow(clock, 503)).toBe(window)
  })
})

describe('WAV 파일', () => {
  it('16비트 PCM 모노 머리말과 샘플 (−1~1 밖은 잘라 낸다)', () => {
    const wav = new DataView(encodeWav(Float32Array.of(0, 0.5, -1, 2), 48_000))
    const text = (offset: number, length: number) =>
      String.fromCharCode(...Array.from({ length }, (_, i) => wav.getUint8(offset + i)))
    expect(text(0, 4)).toBe('RIFF')
    expect(text(8, 4)).toBe('WAVE')
    expect(wav.getUint32(4, true)).toBe(36 + 8)
    expect(wav.getUint16(22, true)).toBe(1) // 채널
    expect(wav.getUint32(24, true)).toBe(48_000)
    expect(wav.getUint16(34, true)).toBe(16)
    expect(wav.getUint32(40, true)).toBe(8)
    expect([0, 1, 2, 3].map((i) => wav.getInt16(44 + i * 2, true))).toEqual([0, 16384, -32768, 32767])
  })

  it('파일 이름: Ullim-날짜-시각.wav', () => {
    expect(exportFileName(new Date(2026, 9, 25, 20, 12))).toBe('Ullim-20261025-2012.wav')
  })

  it('여러 채널은 평균해서 하나로, 5분이 넘으면 앞 5분만', () => {
    const { samples, wasTruncated } = mixToMono([Float32Array.of(1, 0, 0.5), Float32Array.of(0, 0, 0.5)], 1)
    expect(Array.from(samples)).toEqual([0.5, 0, 0.5])
    expect(wasTruncated).toBe(false)
    const long = mixToMono([new Float32Array(400)], 1)
    expect(long.samples).toHaveLength(300)
    expect(long.wasTruncated).toBe(true)
  })
})

describe('내보내기', () => {
  it('저장·공유하는 WAV는 원래 소리(키우기 전)로 만들고, 이름은 녹음한 때로', () => {
    const take = makeTake({
      samples: new Float32Array(48_000).fill(0.01),
      sampleRate: 48_000,
      startTime: 0,
      playbackGain: 15.85,
      recordedAt: new Date(2026, 9, 25, 18, 50),
      title: '방금 녹음',
      readings: [],
      graphDuration: 60,
      recordingStart: 0,
      round: 1,
    })
    const file = takeWavFile(take)
    expect(file.name).toBe('Ullim-20261025-1850.wav')
    expect(file.type).toBe('audio/wav')
    expect(file.size).toBe(44 + 48_000 * 2)
  })
})
