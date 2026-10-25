/** 닫힌 범위 [lower, upper] (Swift의 `ClosedRange<Double>`). 목표 범위·세로축·분석 범위에 쓴다. */
export interface Range {
  readonly lower: number
  readonly upper: number
}

export function range(lower: number, upper: number): Range {
  return { lower, upper }
}

export function contains(r: Range, value: number): boolean {
  return value >= r.lower && value <= r.upper
}
