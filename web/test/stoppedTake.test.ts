import { describe, expect, it } from 'vitest'
import type { PitchReading } from '../src/dsp/pitchHistory'
import { keepsEarlierTake, makeTake, MINIMUM_STOPPED_TAKE_VOICED_SECONDS, takeVoicedSeconds, type RecordedTake } from '../src/practice/take'

// 정지로 끊은 빈 녹음이 마지막 녹음을 덮어쓰던 버그 (2026-10-26 에뮬레이터에서 실제로 녹음을 잃음, 2026-10-30 고침).
// iOS `StoppedTakeTests`와 같은 규칙: 목소리가 0.5초보다 짧고 그 전 녹음이 있으면 그 전 녹음을 그대로 둔다.

const SAMPLE_RATE = 48_000
const INTERVAL = 1024 / SAMPLE_RATE // [s] 점 간격 (48 kHz에서 약 21.3 ms)

/** `seconds`초 녹음. 앞 `voicedSeconds`초만 180 Hz 목소리가 잡히고 나머지는 무음인 점 */
function take(seconds: number, voicedSeconds: number, startTime = 0): RecordedTake {
  const readings: PitchReading[] = []
  for (let t = INTERVAL / 2; t < seconds; t += INTERVAL) {
    readings.push({ time: startTime + t, frequency: t < voicedSeconds ? 180 : null })
  }
  return makeTake({
    samples: new Float32Array(Math.round(seconds * SAMPLE_RATE)),
    sampleRate: SAMPLE_RATE,
    startTime,
    playbackGain: 1,
    recordedAt: new Date(),
    title: '방금 녹음',
    archiveTitle: '',
    language: 'ko',
    readings,
    graphDuration: seconds,
    recordingStart: startTime,
    round: 1,
  })
}

describe('정지로 끊은 녹음', () => {
  const earlier = take(5, 5)

  it('목소리가 없으면 그 전 녹음을 그대로 둔다', () => {
    const silent = take(4, 0, 20)
    expect(takeVoicedSeconds(silent)).toBe(0)
    expect(keepsEarlierTake(silent, earlier)).toBe(true)
  })

  it('목소리가 0.5초보다 짧으면 버리고, 넘으면 새 녹음으로 남긴다', () => {
    const short = take(4, 0.3, 20)
    expect(takeVoicedSeconds(short)).toBeGreaterThan(0)
    expect(takeVoicedSeconds(short)).toBeLessThan(MINIMUM_STOPPED_TAKE_VOICED_SECONDS)
    expect(keepsEarlierTake(short, earlier)).toBe(true)

    const spoken = take(4, 1, 40)
    expect(takeVoicedSeconds(spoken)).toBeGreaterThanOrEqual(MINIMUM_STOPPED_TAKE_VOICED_SECONDS)
    expect(keepsEarlierTake(spoken, earlier)).toBe(false)
  })

  it('그 전 녹음이 없으면 빈 녹음도 남긴다', () => {
    expect(keepsEarlierTake(take(4, 0), null)).toBe(false)
  })

  it('iOS와 같은 기준값', () => {
    expect(MINIMUM_STOPPED_TAKE_VOICED_SECONDS).toBe(0.5)
  })
})
