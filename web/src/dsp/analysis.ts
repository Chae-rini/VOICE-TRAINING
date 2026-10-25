import { FormantAnalyzer } from './formantAnalyzer'
import { PitchDetector, rootMeanSquare } from './pitchDetector'
import type { PitchReading } from './pitchHistory'
import { LevelMeter } from './voiceMeters'

/**
 * 소리 전체를 연습할 때와 같은 방식(2048샘플 창을 절반씩 겹쳐 밀기)으로 처음부터 끝까지 분석한다
 * (iOS `AudioFileAnalyzer.pitchReadings`). 점의 시각은 창 한가운데 [s, 소리 처음부터].
 * 목소리가 잡힌 조각에서만 포먼트를 잰다 (무음·잡음의 가짜 울림을 피함).
 */
export function analyzeSamples(samples: Float32Array, sampleRate: number): PitchReading[] {
  const detector = new PitchDetector(sampleRate)
  const formantAnalyzer = new FormantAnalyzer(sampleRate)
  const frameLength = detector.frameLength
  const hopLength = frameLength / 2
  const readings: PitchReading[] = []
  for (let start = 0; start + frameLength <= samples.length; start += hopLength) {
    const frame = samples.subarray(start, start + frameLength)
    const estimate = detector.detect(frame)
    readings.push({
      time: (start + frameLength / 2) / sampleRate,
      frequency: estimate?.frequency ?? null,
      formants: estimate === null ? null : formantAnalyzer.estimate(frame),
      level: LevelMeter.dBFS(rootMeanSquare(frame)),
    })
  }
  return readings
}

/** 재생할 때 가장 큰 순간을 맞출 높이. 약 −1 dBFS (1.0이 최대). */
export const PLAYBACK_PEAK = 0.89
/** 재생할 때 키울 수 있는 최대 배율. 약 +24 dB. 잡음만 있는 녹음까지 크게 키우지 않기 위한 한계. */
export const MAX_PLAYBACK_GAIN = 15.85

/**
 * 녹음에서 가장 큰 순간의 크기(`peak`, 0~1)를 보고 재생할 때 곱할 배율을 정한다 (iOS `TakeRecorder.playbackGain`).
 * 자동 음량 조절을 끄고 받은 녹음은 작게 들어오므로, 가장 큰 순간이 `PLAYBACK_PEAK`가 되도록 키운다.
 * 이미 큰 녹음은 줄이지 않고(최소 1배), 너무 작은 녹음은 `MAX_PLAYBACK_GAIN`까지만 키운다.
 */
export function playbackGain(peak: number): number {
  if (!(peak > 0)) return 1
  return Math.min(Math.max(PLAYBACK_PEAK / peak, 1), MAX_PLAYBACK_GAIN)
}

/**
 * 녹음 묶음에 넣을 점: 소리 구간 [startTime, endTime]에 든 점만 (iOS `RecordedTake`).
 * 요약·저장·공유·다시 듣기가 모두 이 점만 써야 소리와 수치가 어긋나지 않는다 (2026-10-25 버그 ①).
 */
export function readingsInTake(readings: readonly PitchReading[], startTime: number, endTime: number): PitchReading[] {
  return readings.filter((reading) => reading.time >= startTime && reading.time <= endTime)
}
