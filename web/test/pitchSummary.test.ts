import { describe, expect, it } from 'vitest'
import type { PitchReading } from '../src/dsp/pitchHistory'
import { PitchSummary } from '../src/dsp/pitchSummary'
import { range } from '../src/dsp/range'

// iOS VoicePracticeTests/RecordingImportTests.swift의 PitchSummaryTests를 옮겼다.
describe('PitchSummary (요약 카드 수치·AI 요청문)', () => {
  /** 0.02초 간격, 가운데 무음 2개를 낀 다섯 점: 100, 150, 200, 250, 300 Hz */
  const readings: PitchReading[] = [
    { time: 0.0, frequency: 100 },
    { time: 0.02, frequency: 150 },
    { time: 0.04, frequency: null },
    { time: 0.06, frequency: 200 },
    { time: 0.08, frequency: null },
    { time: 0.1, frequency: 250 },
    { time: 0.12, frequency: 300 },
  ]

  it('중앙값·아래 10%·위 10%·목표 범위 안 비율·목소리 시간', () => {
    const summary = PitchSummary.fromReadings(readings, 3, range(180, 220))!
    expect(summary.median).toBe(200)
    expect(Math.abs(summary.p10 - 120)).toBeLessThan(1e-9) // 100과 150 사이 40% 지점
    expect(Math.abs(summary.p90 - 280)).toBeLessThan(1e-9) // 250과 300 사이 60% 지점
    expect(Math.abs(summary.inTargetFraction! - 0.2)).toBeLessThan(1e-9)
    expect(Math.abs(summary.voicedSeconds - 0.1)).toBeLessThan(1e-9)
  })

  it('목소리가 한 번도 안 잡혔으면 요약이 없다', () => {
    const silent: PitchReading[] = [
      { time: 0, frequency: null },
      { time: 0.02, frequency: null },
    ]
    expect(PitchSummary.fromReadings(silent, 1, range(180, 220))).toBeNull()
  })

  it('목표 범위가 아직 없으면 비율을 비워 두고, 요청문에도 정하지 않았다고 쓴다', () => {
    const summary = PitchSummary.fromReadings(readings, 3, null)!
    expect(summary.inTargetFraction).toBeNull()
    const text = summary.feedbackRequest('방금 녹음', true)
    expect(text).toContain('내 목표 범위: 아직 정하지 않음')
    expect(text).toContain('높이거나 낮추는 방향은 가정하지 말아 주세요')
  })

  it('요청문은 앱을 ‘울림’으로 소개한다 (내부 이름 VoicePractice는 쓰지 않는다)', () => {
    const summary = PitchSummary.fromReadings(readings, 3, range(180, 220))!
    for (const includesAudio of [true, false]) {
      const text = summary.feedbackRequest('방금 녹음', includesAudio)
      expect(text.startsWith('[울림 · 보이스 트레이닝 녹음 피드백 요청]')).toBe(true)
      expect(text).toContain('보이스 트레이닝 앱 ‘울림’이 기기 안에서 직접 잰 값')
      expect(text).not.toContain('VoicePractice')
    }
  })

  it.each([
    [45, '45초'],
    [60, '1분'],
    [83.4, '1분 23초'],
  ])('녹음 길이 표시: %f초 → %s', (seconds, expected) => {
    expect(PitchSummary.durationLabel(seconds)).toBe(expected)
  })

  it('피드백 요청문에 수치·목표 범위·요청 관점이 들어간다', () => {
    const text = PitchSummary.fromReadings(readings, 83, range(180, 220))!.feedbackRequest('방금 녹음', true)
    for (const expected of [
      '방금 녹음 (1분 23초)',
      '피치 중앙값: 200 Hz',
      '120~280 Hz',
      '180~220 Hz',
      '20%',
      '문장 끝 안정성',
      '함께 보낸 녹음 파일',
      '성대에 무리가 가지 않는',
      '어둡고 무게감 있는 쪽',
      '높이거나 낮추는 방향은 가정하지 말고',
    ]) {
      expect(text, expected).toContain(expected)
    }
    expect(text).not.toContain('밝고 가벼운 정도') // 한쪽 방향만 전제하던 예전 표현
  })

  it('글만 보낼 때는 파일이 없다고 밝히고, 음색은 짐작하지 말라고 한다', () => {
    const text = PitchSummary.fromReadings(readings, 83, range(180, 220))!.feedbackRequest('방금 녹음', false)
    expect(text).toContain('피치 중앙값: 200 Hz')
    expect(text).toContain('녹음 파일은 보내지 않았어요')
    expect(text).toContain('짐작하지 말아 주세요')
    expect(text).toContain('성대에 무리가 가지 않는')
    expect(text).toContain('높이거나 낮추는 방향은 가정하지 말고')
    expect(text).not.toContain('함께 보낸 녹음 파일')
  })

  it('요청문 전체 모양이 iOS와 같다 (줄 순서·빈 줄)', () => {
    const text = PitchSummary.fromReadings(readings, 83, range(180, 220))!.feedbackRequest('방금 녹음', false)
    expect(text).toBe(
      [
        '[울림 · 보이스 트레이닝 녹음 피드백 요청]',
        '녹음: 방금 녹음 (1분 23초)',
        '',
        '아래 수치는 보이스 트레이닝 앱 ‘울림’이 기기 안에서 직접 잰 값이에요. (YIN 피치 검출, 70~400 Hz)',
        '- 목소리가 잡힌 시간: 0.1초',
        '- 피치 중앙값: 200 Hz',
        '- 피치 범위(아래 10%~위 10%): 120~280 Hz',
        '- 내 목표 범위: 180~220 Hz (목표 범위 안 비율 20%)',
        '',
        '녹음 파일은 보내지 않았어요. 위 수치를 목표 범위와 비교해 해석하고, 다음 연습에서 해 볼 만한 점을 알려 주세요.',
        '떨림·허스키함·공명 같은 음색은 수치만으로는 알 수 없으니 짐작하지 말아 주세요.',
        '목소리를 높이거나 낮추는 방향은 가정하지 말고, 위의 내 목표 범위를 기준으로 봐 주세요.',
        '성대에 무리가 가지 않는 방향으로 알려 주세요.',
        '수치는 자동 측정이라 오차가 있을 수 있어요.',
      ].join('\n'),
    )
  })
})
