import { describe, expect, it } from 'vitest'
import { GraphWindow } from '../src/dsp/graphWindow'
import { clockEndTime, clockIsMoving, clockWindow, PitchHistory, type GraphClock } from '../src/dsp/pitchHistory'
import { range } from '../src/dsp/range'

// iOS VoicePracticeTests/GraphWindowTests.swift를 옮겼다. 녹음 통(TakeRecorder)과 함께 보는 테스트는 W4에서 옮긴다.
describe('GraphWindow (가로축)', () => {
  it('녹음 중: 오른쪽 끝이 늘 지금이고, 녹음을 시작한 때(시작선)는 왼쪽으로 흘러간다', () => {
    const clock: GraphClock = { kind: 'live', start: 100, duration: 60, round: 1 }
    for (const now of [100, 130, 160]) {
      const window = clockWindow(clock, now)!
      expect(window.end).toBe(now)
      expect(window.duration).toBe(60)
      expect(window.recordingStart).toBe(100)
      expect(window.position(now)).toBe(1)
    }
    // 30초 녹음했으면 시작선은 가운데, 시작선 왼쪽은 비어 있다
    expect(Math.abs(clockWindow(clock, 130)!.position(100) - 0.5)).toBeLessThan(1e-12)
    expect(clockEndTime(clock, 130)).toBe(130)
  })

  it('녹음 시작선: 첫 녹음은 ‘시작’, 다시 녹음하면 ‘2번째’ 경계선. 녹음 시작이 가로축 안일 때만 긋는다', () => {
    const first = clockWindow({ kind: 'live', start: 100, duration: 60, round: 1 }, 120)!
    expect(first.startLabel).toBe('시작')
    expect(first.isRoundBoundary).toBe(false)
    expect(first.showsStartLine).toBe(true)
    expect(Math.abs(first.position(100) - 2 / 3)).toBeLessThan(1e-12) // 20초 전 = 오른쪽에서 1/3

    const second = clockWindow({ kind: 'live', start: 300, duration: 60, round: 2 }, 330)!
    expect(second.startLabel).toBe('2번째')
    expect(second.isRoundBoundary).toBe(true)
    expect(second.showsStartLine).toBe(true)

    // 들려줄 길이보다 오래 녹음하면 시작선은 왼쪽 밖으로 나가 긋지 않는다
    expect(clockWindow({ kind: 'live', start: 100, duration: 60, round: 1 }, 175)!.showsStartLine).toBe(false)
    // 녹음의 첫 소리가 녹음 시작보다 몇 ms 늦어도(녹음 통 시각) 왼쪽 끝의 시작선은 긋는다
    expect(new GraphWindow(100.002, 60, 100, 3).showsStartLine).toBe(true)
    // 불러온 파일은 시작선이 없다
    expect(new GraphWindow(0, 12).showsStartLine).toBe(false)
  })

  it('녹음 중: 들려줄 길이보다 오래 녹음하면 시작선은 왼쪽 밖으로 나가고, 시간 글자는 계속 녹음 시작부터 센다', () => {
    const window = clockWindow({ kind: 'live', start: 100, duration: 60, round: 1 }, 175)!
    expect(window.start).toBe(115)
    expect(window.end).toBe(175)
    expect(window.recordingStart).toBe(100)
    expect(window.showsStartLine).toBe(false)
    expect(window.ticks[0].label).toBe('0:20')
  })

  it('녹음 하나의 가로축: 녹음할 때의 들려줄 길이만큼, 녹음이 더 길면 녹음 길이만큼', () => {
    // 4초 녹음(50~54초), 들려줄 길이 1분: 오른쪽 끝이 녹음 끝, 왼쪽은 비어 있다 (녹음하던 화면이 멈춘 모습 그대로)
    const short = GraphWindow.forTake({ endTime: 54, duration: 4, graphDuration: 60, recordingStart: 50, round: null })
    expect(short).toEqual(new GraphWindow(-6, 60, 50, null))
    expect(short.showsStartLine).toBe(true)
    const long = GraphWindow.forTake({ endTime: 62, duration: 12, graphDuration: 10, recordingStart: 50, round: null })
    expect(Math.abs(long.duration - 12)).toBeLessThan(1e-9)
    // 불러온 파일은 파일 길이만큼, 시작선 없음
    const imported = GraphWindow.forTake({ endTime: 3, duration: 3, graphDuration: 0, recordingStart: null, round: null })
    expect(imported).toEqual(new GraphWindow(0, 3, null, null))
  })

  it.each([
    [10, 2],
    [30, 5],
    [60, 10],
    [90, 15],
    [120, 30],
    [180, 30],
  ])('시간 눈금: 가로축 %i초면 %i초 간격 (6개 이하가 되는 가장 촘촘한 간격)', (duration, expected) => {
    expect(new GraphWindow(0, duration).tickStep).toBe(expected)
  })

  it('시간 눈금 글자는 녹음을 시작한 때부터 센 분:초다 (흐른 뒤에도 이어서 센다)', () => {
    const filling = new GraphWindow(100, 60, 100)
    expect(filling.ticks.map((t) => t.label)).toEqual(['0:00', '0:10', '0:20', '0:30', '0:40', '0:50', '1:00'])
    expect(filling.ticks[0].time).toBe(100)

    const sliding = new GraphWindow(183, 60, 100) // 1:23 ~ 2:23
    expect(sliding.ticks.map((t) => t.label)).toEqual(['1:30', '1:40', '1:50', '2:00', '2:10', '2:20'])
    expect(sliding.ticks[0].time).toBe(190)

    // 녹음을 시작하기 전(시작선 왼쪽의 빈 곳)에는 눈금이 없다
    expect(new GraphWindow(40, 60, 70).ticks.map((t) => t.label)).toEqual(['0:00', '0:10', '0:20', '0:30'])

    expect(GraphWindow.timeLabel(0)).toBe('0:00')
    expect(GraphWindow.timeLabel(75)).toBe('1:15')
    expect(GraphWindow.timeLabel(180)).toBe('3:00')
  })

  it('짧은 가로축은 점을 그대로 쓰고, 긴 가로축은 픽셀 열마다 한 점으로 묶되 무음 구간은 끊는다', () => {
    // 3분 동안 0.02초마다: 처음 60초 목소리(150 Hz), 60~62초 무음, 그 뒤 다시 목소리(250 Hz)
    const history = new PitchHistory(200)
    history.append(
      Array.from({ length: 9000 }, (_, index) => {
        const time = index * 0.02
        return { time, frequency: time >= 60 && time < 62 ? null : time < 60 ? 150 : 250 }
      }),
    )
    const long = new GraphWindow(0, 180)
    const segments = history.displaySegments(long, 180, 300)
    expect(segments).toHaveLength(2)
    expect(segments.flat().length).toBeLessThanOrEqual(300)
    expect(segments[0].every((r) => r.frequency === 150)).toBe(true)
    expect(segments[1].every((r) => r.frequency === 250)).toBe(true)

    // ‘지금’까지만 그린다
    const untilNow = history.displaySegments(long, 30, 300)
    expect(untilNow.flat().every((r) => r.time <= 30 + 180 / 300)).toBe(true)

    // 10초 가로축(300pt면 1pt에 점 1~2개)은 묶지 않는다
    const short = history.displaySegments(new GraphWindow(0, 10), 10, 300)
    expect(short.flat().length).toBe(history.readingsIn(range(-0.5, 10)).filter((r) => r.frequency !== null).length)
  })
})

describe('GraphClock', () => {
  it('다시 듣는 중: 재생 위치가 녹음 첫 소리부터 재생된 만큼 움직이고, 멈춘 화면은 움직이지 않는다', () => {
    const window = new GraphWindow(40, 60, 50, 1)
    const replay: GraphClock = { kind: 'replay', window, takeStart: 50, playbackStart: 1000 }
    expect(clockEndTime(replay, 1003.5)).toBe(53.5)
    expect(clockWindow(replay, 1003.5)).toBe(window)
    expect(clockIsMoving(replay)).toBe(true)

    const frozen: GraphClock = { kind: 'frozen', window, at: 100 }
    expect(clockEndTime(frozen, 5000)).toBe(100)
    expect(clockIsMoving(frozen)).toBe(false)
    expect(clockWindow({ kind: 'frozen', window: null, at: null }, 7)).toBeNull()
  })
})

describe('PitchHistory', () => {
  it('보관 길이보다 오래된 점은 버리고, 끊긴 곳에서 선을 나눈다', () => {
    const history = new PitchHistory(1)
    history.append([0, 0.5, 1.0, 1.5, 2.0].map((time) => ({ time, frequency: 150 })))
    expect(history.readings.map((r) => r.time)).toEqual([1.0, 1.5, 2.0])

    const gaps = new PitchHistory()
    gaps.append([
      { time: 0, frequency: 150 },
      { time: 0.02, frequency: 151 },
      { time: 0.04, frequency: null },
      { time: 0.06, frequency: 152 }, // 점 하나 빠진 곳은 잇는다 (0.04초 < 0.05초)
      { time: 0.2, frequency: 153 }, // 긴 무음은 끊는다
    ])
    expect(gaps.voicedSegments().map((segment) => segment.length)).toEqual([3, 1])
    expect(gaps.frequencyAt(0.1)).toBe(152)
    expect(gaps.frequencyAt(0.5)).toBe(153) // 0.3초 전까지는 그 값
    expect(gaps.frequencyAt(0.6)).toBeNull() // 0.3초보다 오래됨
  })
})
