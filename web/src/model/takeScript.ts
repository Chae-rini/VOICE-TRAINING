import type { PitchReading } from '../dsp/pitchHistory'

/**
 * 녹음 하나가 읽은 대본 (iOS `TakeScript`, 2026-11-04~). 같은 대본을 읽은 녹음끼리 공명 밝기(F2)를 견주는 데 쓴다.
 * 문장 속 F2는 말한 모음에 따라 달라서, 다른 글을 읽은 녹음끼리는 비교가 흐려진다.
 */
export interface TakeScript {
  /** `PracticeScript.id` (가져온 내 대본은 `my-`로 시작) */
  readonly id: string
  /** 그때의 제목. 내 대본을 지운 뒤에도 기록에서 이름을 보여 줄 수 있게 같이 남긴다 */
  readonly title: string
}

export function sameScript(a: TakeScript | null, b: TakeScript | null): boolean {
  return a === b || (a !== null && b !== null && a.id === b.id && a.title === b.title)
}

/** 기록 파일에서 읽은 값이 대본 모양이면 그 대본, 아니면 null (모양이 다른 칸은 대본이 없는 것으로) */
export function takeScriptOf(value: unknown): TakeScript | null {
  const s = value as TakeScript | null | undefined
  return typeof s === 'object' && s !== null && typeof s.id === 'string' && typeof s.title === 'string'
    ? { id: s.id, title: s.title }
    : null
}

/**
 * [높이] 화면의 대본이 바뀐 시각을 적어 두고, 녹음 하나가 어느 대본을 읽은 것인지 정한다 (iOS `ScriptTimeline`).
 * 반복 루프는 다 들으면 저절로 다시 녹음하므로, 녹음이 시작된 뒤에 다음 대본으로 넘기는 일이 흔하다.
 * 그래서 녹음 내내가 아니라 목소리가 잡힌 동안 화면에 있던 대본으로 정한다.
 * 시각은 피치 점과 같은 시계(소리 시계, `session.now()`)다.
 */
export class ScriptTimeline {
  /**
   * 목소리가 잡힌 점 중 이 비율 이상이 한 대본을 띄워 둔 동안 나와야 그 대본을 읽은 녹음으로 본다 (임시값, iOS와 같은 값).
   * 대본을 넘기기 앞뒤로 짧게 낸 소리(‘음’ 같은)는 견디고, 두 대본을 이어 읽은 녹음은 빼려고.
   */
  static readonly minimumShare = 0.9

  /** script가 null: 대본이 아닌 문장을 보거나 대본 화면이 사라졌다 */
  #changes: { readonly time: number; readonly script: TakeScript | null }[] = []

  /** 화면의 대본이 바뀌었을 때 부른다. 같은 대본이 다시 오면 아무것도 하지 않는다 */
  show(script: TakeScript | null, time: number): void {
    const last = this.#changes.at(-1)
    if (last !== undefined && sameScript(last.script, script)) return
    this.#changes.push({ time, script })
  }

  /**
   * 새 녹음을 시작할 때 부른다. 지금 화면에 있는 대본 하나만 남기고, 그 대본이 처음부터 화면에 있던 것으로 둔다.
   * iOS `forget(before:)`과 같은 일이지만 시각으로 자르지 않는다: 웹은 마이크를 켜기 전에는 소리 시계가 없어 다른 시계로 적으므로,
   * 그때 적은 시각은 녹음의 점과 견줄 수 없다. 녹음 중에는 마이크가 켜져 있어 시계가 하나다.
   */
  restart(): void {
    const last = this.#changes.at(-1)
    this.#changes = last === undefined ? [] : [{ time: -Infinity, script: last.script }]
  }

  /** 그 시각에 화면에 있던 대본 */
  scriptAt(time: number): TakeScript | null {
    for (let i = this.#changes.length - 1; i >= 0; i--) {
      if (this.#changes[i].time <= time) return this.#changes[i].script
    }
    return null
  }

  /**
   * 녹음의 점 중 목소리가 잡힌 점을 그때 화면의 대본별로 세어, `minimumShare` 이상을 차지한 대본.
   * 목소리가 없거나, 대본이 섞였거나, 대본이 아닌 것을 보며 말했으면 null.
   */
  scriptFor(readings: Iterable<PitchReading>): TakeScript | null {
    const counts: { script: TakeScript | null; count: number }[] = []
    let voiced = 0
    for (const reading of readings) {
      if (reading.frequency === null) continue
      const script = this.scriptAt(reading.time)
      const entry = counts.find((c) => sameScript(c.script, script))
      if (entry === undefined) counts.push({ script, count: 1 })
      else entry.count += 1
      voiced += 1
    }
    if (voiced === 0) return null
    const most = counts.reduce((a, b) => (b.count > a.count ? b : a))
    return most.script !== null && most.count / voiced >= ScriptTimeline.minimumShare ? most.script : null
  }
}
