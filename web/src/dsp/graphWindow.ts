/**
 * 피치 그래프의 가로축에 보일 시간 구간 [s] (iOS `Models/GraphWindow.swift`).
 * 가로축 길이는 ‘들려줄 길이’(10초~3분)를 따른다. 오른쪽 끝이 늘 "지금"이고, 곡선과 시간 눈금이 함께 왼쪽으로 흐른다
 * (곡선의 머리가 한자리에 있어서 지금 높이를 읽기 쉽다, 2026-10-25 사용자 요청).
 */
export class GraphWindow {
  constructor(
    /** [s] 왼쪽 끝 시각 */
    readonly start: number,
    /** [s] 가로축 길이 */
    readonly duration: number,
    /** [s] 녹음을 시작한 시각. 불러온 파일처럼 없으면 null (시간은 왼쪽 끝부터 센다). */
    readonly recordingStart: number | null = null,
    /** 반복 루프에서 몇 번째 녹음인지 (1부터). 2번째부터는 시작선 대신 "2번째" 경계선을 긋는다. */
    readonly round: number | null = null,
  ) {}

  /** 녹음 시작 세로선의 글자: 첫 녹음은 "시작", 반복 루프에서 다시 녹음한 것은 "2번째"처럼. */
  get startLabel(): string {
    return this.round !== null && this.round > 1 ? `${this.round}번째` : '시작'
  }

  /** 다시 녹음한 경계선인지 (시작선과 모양을 다르게 그린다) */
  get isRoundBoundary(): boolean {
    return (this.round ?? 1) > 1
  }

  /** 녹음 시작 세로선을 그릴지: 녹음을 시작한 때가 가로축 안에 있을 때만 */
  get showsStartLine(): boolean {
    if (this.recordingStart === null) return false
    return this.recordingStart >= this.start - 0.01 && this.recordingStart <= this.end
  }

  /** [s] 오른쪽 끝 시각 */
  get end(): number {
    return this.start + this.duration
  }

  /** 0(왼쪽 끝)~1(오른쪽 끝). 구간 밖이면 0보다 작거나 1보다 크다. */
  position(time: number): number {
    return (time - this.start) / this.duration
  }

  /**
   * 녹음 중의 구간: 오른쪽 끝이 지금, 왼쪽 끝은 `duration`초 전. 이 구간(최근 `duration`초)은
   * 녹음 통이 남겨 두는 소리, 곧 다시 들을 수 있는 구간과 같다.
   */
  static live(recordingStart: number, now: number, duration: number, round: number | null = null): GraphWindow {
    return new GraphWindow(now - duration, duration, recordingStart, round)
  }

  /**
   * 녹음 하나를 보여 줄 가로축 (iOS `RecordedTake.graphWindow`): 녹음이 끝난 때가 오른쪽 끝,
   * 길이는 녹음할 때의 그래프 길이(들려줄 길이). 녹음이 더 길면 녹음 길이만큼.
   */
  static forTake(take: {
    endTime: number
    duration: number
    graphDuration: number
    recordingStart: number | null
    round: number | null
  }): GraphWindow {
    const length = Math.max(take.duration, take.graphDuration)
    return new GraphWindow(take.endTime - length, length, take.recordingStart, take.round)
  }

  /** 가로축 눈금 간격 후보 [s]. 눈금이 6개 이하가 되는 가장 촘촘한 간격을 쓴다. */
  static readonly tickSteps: readonly number[] = [2, 5, 10, 15, 30, 60]

  /** 가로축 눈금 간격 [s] */
  get tickStep(): number {
    return GraphWindow.tickSteps.find((step) => this.duration / step <= 6) ?? Math.ceil(this.duration / 6 / 60) * 60
  }

  /**
   * 가로축 눈금: 녹음 시작(없으면 왼쪽 끝)부터 `tickStep`마다, 구간 안에 드는 시각과 "1:30" 같은 글자.
   * 녹음을 시작하기 전(시작선 왼쪽의 빈 곳)에는 눈금을 두지 않는다.
   */
  get ticks(): { time: number; label: string }[] {
    const origin = this.recordingStart ?? this.start
    const step = this.tickStep
    const first = Math.max(Math.ceil((this.start - origin) / step - 1e-9), 0)
    const last = Math.floor((this.end - origin) / step + 1e-9)
    const result: { time: number; label: string }[] = []
    for (let index = first; index <= last; index++) {
      result.push({ time: origin + index * step, label: GraphWindow.timeLabel(index * step) })
    }
    return result
  }

  /** 예: 0 → "0:00", 75 → "1:15" */
  static timeLabel(seconds: number): string {
    const total = Math.max(Math.round(seconds), 0)
    return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, '0')}`
  }
}
