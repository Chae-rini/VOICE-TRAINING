import type { PitchReading } from '../dsp/pitchHistory'
import { PitchSummary } from '../dsp/pitchSummary'
import type { Range } from '../dsp/range'
import { ResonanceMeter } from '../dsp/voiceMeters'
import { totalLabel } from '../model/history'
import {
  languageLabel,
  newRecordId,
  pitchNumbers,
  pitchSummaryOf,
  type PracticeLanguage,
  type SessionRecord,
} from '../model/records'
import { formatDayTime } from '../text/dates'

/** 녹음 한 번의 요약 */
export interface TakeSummary {
  /** 연습 안에서 몇 번째 녹음인지 (1부터). 목소리가 안 잡힌 녹음은 빠지므로 건너뛸 수 있다 */
  readonly round: number
  readonly endedAt: Date
  /** `duration`은 녹음 길이, `target`은 그 녹음을 마친 때의 목표 범위 */
  readonly pitch: PitchSummary
}

/** 정지했을 때 남길 내용 */
export interface SessionSummary {
  readonly startedAt: Date
  readonly endedAt: Date
  /** 녹음한 횟수 (듣기 뒤 다시 녹음할 때마다 1씩) */
  readonly takeCount: number
  readonly language: PracticeLanguage
  /** 연습 전체를 하나로 모은 피치 요약. `duration`은 시작~정지 시간 */
  readonly pitch: PitchSummary
  readonly takes: readonly TakeSummary[]
  /** [Hz] 연습 전체의 F2 중앙값. 포먼트가 충분히 잡히지 않았으면 null */
  readonly f2Median: number | null
}

/**
 * 연습 한 번(‘반복 루프 재생’부터 정지까지) 동안, 녹음 여러 번에 걸쳐 잡힌 목소리 높이를 모은다 (iOS `PracticeSessionLog`).
 * 녹음마다의 요약도 쌓는다 (다음 녹음이 시작되면 요약 카드가 사라지므로, 나중에 [기록]에서 보고 보낼 수 있게).
 * 소리는 모으지 않고 숫자만 모은다. 정지하면 연습 기록 하나가 된다.
 */
export class PracticeSessionLog {
  /** [s] 이보다 짧은 연습은 남기지 않는다 (잘못 눌렀다 바로 멈춘 경우 등) */
  static readonly minimumSeconds = 30
  /** [s] 목소리가 이보다 짧게 잡힌 연습은 남기지 않는다 */
  static readonly minimumVoicedSeconds = 5
  /** [s] 이웃한 점 사이가 이보다 벌어지면 그 사이는 목소리 시간으로 세지 않는다 (분석 간격은 약 0.02초) */
  static readonly maxReadingGap = 0.1

  takeCount = 0
  readonly takes: TakeSummary[] = []
  /** [Hz] 잡힌 목소리 높이들 */
  readonly voiced: number[] = []
  /** [s] 목소리가 잡힌 시간 */
  voicedSeconds = 0
  /** 목소리와 포먼트가 잡힌 점들 (연습 전체의 F2 중앙값을 내는 데만 쓴다) */
  readonly #formantReadings: PitchReading[] = []
  /** [s] 바로 앞 점의 시각. 녹음을 새로 시작하면 지운다 (녹음 사이의 빈 시간을 목소리로 세지 않게) */
  #lastTime: number | null = null

  constructor(
    readonly startedAt: Date,
    readonly language: PracticeLanguage,
  ) {}

  /** 녹음을 새로 시작할 때 부른다 (처음, 그리고 듣기 뒤 다시 녹음할 때마다) */
  beginTake(): void {
    this.takeCount += 1
    this.#lastTime = null
  }

  /** 녹음 중에 들어온 피치 점들을 더한다. 목소리가 잡힌 점마다 앞 점과의 간격만큼을 목소리 시간으로 센다 */
  add(readings: readonly PitchReading[]): void {
    for (const reading of readings) {
      if (reading.frequency !== null) {
        this.voiced.push(reading.frequency)
        if (reading.formants) this.#formantReadings.push(reading)
        if (this.#lastTime !== null) {
          this.voicedSeconds += Math.min(Math.max(reading.time - this.#lastTime, 0), PracticeSessionLog.maxReadingGap)
        }
      }
      this.#lastTime = reading.time
    }
  }

  /**
   * 녹음 한 번이 끝났을 때 그 녹음의 요약을 남긴다. 목소리가 한 번도 안 잡혔으면 남기지 않는다.
   * 요약 카드와 같은 점·길이를 넘겨, 카드에 보이던 숫자가 그대로 남게 한다.
   */
  finishTake(readings: readonly PitchReading[], duration: number, target: Range | null, endedAt: Date): void {
    if (this.takeCount === 0) return
    const pitch = PitchSummary.fromReadings(readings, duration, target)
    if (pitch !== null) this.takes.push({ round: this.takeCount, endedAt, pitch })
  }

  /** 정지했을 때의 요약. 30초보다 짧은 연습이거나 목소리가 5초보다 짧게 잡혔으면 null (남기지 않음) */
  finish(endedAt: Date, target: Range | null): SessionSummary | null {
    const duration = (endedAt.getTime() - this.startedAt.getTime()) / 1000
    if (duration < PracticeSessionLog.minimumSeconds || this.voicedSeconds < PracticeSessionLog.minimumVoicedSeconds) return null
    const pitch = PitchSummary.fromVoiced(this.voiced, this.voicedSeconds, duration, target)
    if (pitch === null) return null
    return {
      startedAt: this.startedAt,
      endedAt,
      takeCount: this.takeCount,
      language: this.language,
      pitch,
      takes: [...this.takes],
      f2Median: ResonanceMeter.median(this.#formantReadings),
    }
  }
}

/** 기록 파일에 남길 모양으로 */
export function sessionRecord(summary: SessionSummary, id = newRecordId()): SessionRecord {
  return {
    id,
    startedAt: summary.startedAt.toISOString(),
    endedAt: summary.endedAt.toISOString(),
    takeCount: summary.takeCount,
    language: summary.language,
    pitch: pitchNumbers(summary.pitch),
    f2Median: summary.f2Median,
    takes: summary.takes.map((take) => ({ round: take.round, endedAt: take.endedAt.toISOString(), pitch: pitchNumbers(take.pitch) })),
  }
}

/** 저장된 연습 기록을 요약으로 되돌린다 (자세히 화면·요청문용). 녹음마다는 녹음 순서대로 */
export function sessionSummaryOf(record: SessionRecord): SessionSummary {
  return {
    startedAt: new Date(record.startedAt),
    endedAt: new Date(record.endedAt),
    takeCount: record.takeCount,
    language: record.language,
    pitch: pitchSummaryOf(record.pitch),
    takes: [...record.takes]
      .sort((a, b) => a.round - b.round)
      .map((take) => ({ round: take.round, endedAt: new Date(take.endedAt), pitch: pitchSummaryOf(take.pitch) })),
    f2Median: record.f2Median,
  }
}

function sameRange(a: Range | null, b: Range | null): boolean {
  return a === b || (a !== null && b !== null && a.lower === b.lower && a.upper === b.upper)
}

/** 목록 한 줄. 예: "중앙 182 Hz · 165–201 Hz · 목표 안 72%" */
export function takeNumbersLine(take: TakeSummary): string {
  const { pitch } = take
  const parts = [`중앙 ${Math.round(pitch.median)} Hz`, `${Math.round(pitch.p10)}–${Math.round(pitch.p90)} Hz`]
  if (pitch.inTargetFraction !== null) parts.push(`목표 안 ${Math.round(pitch.inTargetFraction * 100)}%`)
  return parts.join(' · ')
}

/** 녹음 한 번의 목표 범위가 연습 기록의 목표 범위(정지한 때)와 다르면 그때 목표 (자세히 화면·요청문용) */
export function takeOwnTarget(take: TakeSummary, sessionTarget: Range | null): Range | null {
  const target = take.pitch.target
  return target !== null && !sameRange(target, sessionTarget) ? target : null
}

/** 요청문 한 줄. 그 녹음의 목표 범위가 정지한 때와 다르면 그때 목표를 함께 적는다 */
export function takeRequestLine(take: TakeSummary, sessionTarget: Range | null): string {
  const { pitch } = take
  let line =
    `- ${take.round}번째 녹음 (${PitchSummary.durationLabel(pitch.duration)}, 목소리 ${pitch.voicedSeconds.toFixed(1)}초): ` +
    `중앙 ${Math.round(pitch.median)} Hz, 범위 ${Math.round(pitch.p10)}~${Math.round(pitch.p90)} Hz`
  if (pitch.target !== null && pitch.inTargetFraction !== null) {
    line += `, 목표 범위 안 ${Math.round(pitch.inTargetFraction * 100)}%`
    const own = takeOwnTarget(take, sessionTarget)
    if (own !== null) line += ` (그때 목표 ${Math.trunc(own.lower)}~${Math.trunc(own.upper)} Hz)`
  }
  return line
}

/**
 * 연습 한 번을 AI 앱에 붙여 넣을 피드백 요청문 (iOS `PracticeSessionLog.Summary.feedbackRequest`). 소리는 남지 않으므로 숫자만 보낸다.
 * 녹음마다의 숫자를 함께 넣어, 한 번의 연습 안에서 어떻게 달라졌는지도 볼 수 있게 한다. 방향을 가정하지 않고, 음색은 짐작하지 않게.
 */
export function sessionFeedbackRequest(summary: SessionSummary): string {
  const { pitch } = summary
  const takeLines =
    summary.takes.length === 0
      ? '- (녹음마다 기록이 없는 예전 연습이에요)'
      : summary.takes.map((take) => takeRequestLine(take, pitch.target)).join('\n')
  const practiceTime = totalLabel((summary.endedAt.getTime() - summary.startedAt.getTime()) / 1000)
  return [
    '[울림 · 보이스 트레이닝 연습 피드백 요청]',
    `연습: ${formatDayTime(summary.startedAt)} · 연습 ${practiceTime} · 녹음 ${summary.takeCount}번 · 말한 언어 ${languageLabel(summary.language)}`,
    '',
    PitchSummary.measurementNote,
    '연습 전체',
    `- 목소리가 잡힌 시간: ${pitch.voicedSeconds.toFixed(1)}초`,
    `- 피치 중앙값: ${Math.round(pitch.median)} Hz`,
    `- 피치 범위(아래 10%~위 10%): ${Math.round(pitch.p10)}~${Math.round(pitch.p90)} Hz`,
    `- 내 목표 범위: ${pitch.targetDescription}`,
    '',
    '녹음마다 (‘지금 들어보기’를 누르거나 정지할 때마다 하나, 목소리가 잡힌 녹음만)',
    takeLines,
    '',
    '녹음 파일은 보내지 않았어요. 위 수치를 목표 범위와 비교해 해석하고, 녹음마다 어떻게 달라졌는지와 다음 연습에서 해 볼 만한 점을 알려 주세요.',
    PitchSummary.timbreCaution,
    pitch.directionLine,
    PitchSummary.closingLines,
  ].join('\n')
}
