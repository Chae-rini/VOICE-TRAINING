import { readingsInTake } from '../dsp/analysis'
import { GraphWindow } from '../dsp/graphWindow'
import { PitchHistory, type PitchReading } from '../dsp/pitchHistory'
import { PitchSummary } from '../dsp/pitchSummary'
import type { Range } from '../dsp/range'
import { ResonanceMeter } from '../dsp/voiceMeters'
import type { PracticeLanguage } from '../model/records'

/**
 * 녹음 한 번의 묶음: 원래 소리, 시작 시각과 길이, 그 구간의 피치·포먼트 점 (iOS `RecordedTake`).
 * 요약 카드·AI 공유·파일로 저장·다시 듣기는 모두 이 묶음 안의 것만 쓴다 (소리와 수치가 어긋나지 않게, 2026-10-25 버그 ①).
 */
export interface RecordedTake {
  readonly id: number
  /** 원래 소리 (모노). 들려줄 때만 `playbackGain`을 곱한다 */
  readonly samples: Float32Array
  /** [Hz] */
  readonly sampleRate: number
  /** [s] 첫 샘플의 시각. 피치 점과 같은 시계 (불러온 파일은 0) */
  readonly startTime: number
  /** 다시 들을 때 곱할 배율 (가장 큰 순간이 약 −1 dBFS가 되게, 최대 +24 dB) */
  readonly playbackGain: number
  /** 녹음을 마친(또는 파일을 불러온) 때 */
  readonly recordedAt: Date
  /** 화면에 보일 이름 ("방금 녹음" 또는 불러온 파일 이름) */
  readonly title: string
  /** 기록에 남길 이름: 불러온 파일이면 파일 이름, 앱에서 녹음했으면 빈 글자 */
  readonly archiveTitle: string
  /** 연습 중 녹음이면 그 연습의 말하는 언어. 불러온 파일은 null (남길 때 지금 고른 언어) */
  readonly language: PracticeLanguage | null
  /** 이 소리 구간(첫 샘플~마지막 샘플)의 점 */
  readonly readings: readonly PitchReading[]
  /** [s] 그래프 가로축 길이. 연습 녹음은 녹음할 때의 들려줄 길이, 불러온 파일은 0 (파일 길이만큼) */
  readonly graphDuration: number
  /** [s] 연습 녹음을 시작한 시각 (‘시작’ 선과 가로축 시간의 기준). 불러온 파일은 null */
  readonly recordingStart: number | null
  /** 반복 루프에서 몇 번째 녹음인지 (1부터). 불러온 파일은 null */
  readonly round: number | null
}

let nextTakeId = 1

/** 묶음을 만든다. `readings`에서 이 소리 구간에 든 점만 잘라 담는다 (점의 시각은 분석 창의 한가운데). */
export function makeTake(options: Omit<RecordedTake, 'id' | 'readings'> & { readings: readonly PitchReading[] }): RecordedTake {
  const endTime = options.startTime + options.samples.length / options.sampleRate
  return { ...options, id: nextTakeId++, readings: readingsInTake(options.readings, options.startTime, endTime) }
}

/** [s] 소리 길이 */
export function takeDuration(take: RecordedTake): number {
  return take.samples.length / take.sampleRate
}

/** [s] 마지막 샘플 바로 뒤의 시각 */
export function takeEndTime(take: RecordedTake): number {
  return take.startTime + takeDuration(take)
}

/** 이 녹음의 요약. 목소리가 한 번도 안 잡혔으면 null. */
export function takeSummary(take: RecordedTake, target: Range | null): PitchSummary | null {
  return PitchSummary.fromReadings(take.readings, takeDuration(take), target)
}

/** [Hz] 녹음 전체의 F2 중앙값 (공명 밝기). 포먼트가 충분히 잡히지 않았으면 null. */
export function takeF2Median(take: RecordedTake): number | null {
  return ResonanceMeter.median(take.readings)
}

/** 다시 들을 때 그래프에 그릴 기록 */
export function takeHistory(take: RecordedTake): PitchHistory {
  const history = new PitchHistory(takeDuration(take) + 2)
  history.append(take.readings)
  return history
}

/** 이 녹음을 보여 줄 가로축: 녹음이 끝난 때가 오른쪽 끝, 길이는 들려줄 길이 (녹음이 더 길면 녹음 길이) */
export function takeGraphWindow(take: RecordedTake): GraphWindow {
  return GraphWindow.forTake({
    endTime: takeEndTime(take),
    duration: takeDuration(take),
    graphDuration: take.graphDuration,
    recordingStart: take.recordingStart,
    round: take.round,
  })
}
