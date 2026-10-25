import { describe, expect, it } from 'vitest'
import { GraphWindow } from '../src/dsp/graphWindow'
import type { PitchReading } from '../src/dsp/pitchHistory'
import { range } from '../src/dsp/range'
import { graphDescription, graphLabel, meterDescription, restMessage } from '../src/graph/descriptions'
import { buildCurve, graphHeight, plotRect } from '../src/graph/pitchGraph'

describe('그래프 크기', () => {
  // iOS AudioFileExportTests.graphHeight와 같은 기대값
  it('쓸 수 있는 높이의 45%(대본 읽기 33%), 작은 화면에서도 220·150 이상, 큰 화면에서도 380·280 이하', () => {
    expect(graphHeight(600, false)).toBeCloseTo(270, 9)
    expect(graphHeight(600, true)).toBeCloseTo(198, 9)
    expect(graphHeight(300, false)).toBe(220)
    expect(graphHeight(300, true)).toBe(150)
    expect(graphHeight(1200, false)).toBe(380)
    expect(graphHeight(1200, true)).toBe(280)
  })

  it('왼쪽 34·위 12는 눈금 자리, 아래 24는 시간 자리', () => {
    expect(plotRect(360, 270)).toEqual({ x: 34, y: 12, width: 318, height: 234 })
  })
})

describe('꺾은선 모양', () => {
  const axis = range(70, 170)
  const target = range(100, 120)
  /** 시각 = x, 높이 = y로 그대로 찍는다 */
  const toPoint = (r: PitchReading) => (r.frequency === null ? null : { x: r.time, y: r.frequency })
  const segment = (...frequencies: number[]) => frequencies.map((frequency, i) => ({ time: i, frequency }))

  it('목표 범위 안은 안쪽, 밖은 바깥쪽 (두 점의 가운데 높이로)', () => {
    const shapes = buildCurve([segment(110, 112, 130)], toPoint, axis, target)
    expect(shapes.inside).toHaveLength(1) // 110→112
    expect(shapes.outside).toHaveLength(1) // 112→130 (가운데 121)
    expect(shapes.beyond).toHaveLength(0)
  })

  it('세로축 밖으로 나간 부분은 이어진 점선 하나 (조각마다 끊지 않는다)', () => {
    const shapes = buildCurve([segment(160, 180, 190, 200, 160)], toPoint, axis, target)
    expect(shapes.beyond).toHaveLength(1)
    expect(shapes.beyond[0].map((p) => p.y)).toEqual([180, 190, 200])
    expect(shapes.outside).toHaveLength(2) // 160→180, 200→160 (한쪽은 축 안)
  })

  it('앞뒤로 이어진 점이 없는 외톨이 점은 작은 점으로', () => {
    const shapes = buildCurve([segment(110), segment(150)], toPoint, axis, target)
    expect(shapes.lonelyInside).toEqual([{ x: 0, y: 110 }])
    expect(shapes.lonelyOutside).toEqual([{ x: 0, y: 150 }])
  })

  it('목표 범위가 없으면 모두 바깥쪽(회색)', () => {
    const shapes = buildCurve([segment(110, 112)], toPoint, range(70, 400), null)
    expect(shapes.inside).toHaveLength(0)
    expect(shapes.outside).toHaveLength(1)
  })
})

describe('화면 읽기 프로그램용 설명 (iOS와 같은 문장)', () => {
  it('그래프: 가로축·세로축·녹음 시작부터·목표·기준·지금', () => {
    const window = new GraphWindow(100, 60, 100, 1)
    expect(graphLabel(window)).toBe('목소리 높이 그래프, 가로축 1분')
    expect(
      graphDescription({
        frequency: 152.4,
        window,
        endTime: 135,
        axis: range(85, 225),
        target: range(135, 175),
        baselineMedian: 151.6,
        isReplaying: false,
      }),
    ).toBe('가로축 1분, 세로축 85에서 225 Hz, 녹음 시작부터 0:35, 목표 범위 135에서 175 Hz, 기준 152 Hz, 지금 152 Hz, 목표 범위 안')
    expect(
      graphDescription({
        frequency: null,
        window: new GraphWindow(0, 60),
        endTime: 60,
        axis: range(70, 400),
        target: null,
        baselineMedian: null,
        isReplaying: false,
      }),
    ).toBe('가로축 1분, 세로축 70에서 400 Hz, 목표 범위 없음, 지금 잡힌 목소리 없음')
  })

  it('막대: 음량, 큰 소리, 공명 밝기와 기준 대비 방향, 불확실', () => {
    expect(meterDescription(-24.4, false, { f2: 1650, isUncertain: false }, 1500)).toBe(
      '음량 -24 dBFS, 공명 밝기 F2 1650 Hz, 기준보다 밝은 쪽',
    )
    expect(meterDescription(null, false, null, null)).toBe('음량 없음, 공명 밝기 없음')
    expect(meterDescription(-8, true, { f2: 1500, isUncertain: true }, 1500)).toBe(
      '음량 -8 dBFS, 소리가 꽤 커요, 공명 밝기 F2 1500 Hz, 기준과 비슷, 불확실',
    )
  })

  it('쉬어 가기 안내: 15분마다', () => {
    expect(restMessage(900)).toBe('15분 연습했어요. 목을 잠깐 쉬어 주세요.')
    expect(restMessage(1830)).toBe('30분 연습했어요. 목을 잠깐 쉬어 주세요.')
  })
})
