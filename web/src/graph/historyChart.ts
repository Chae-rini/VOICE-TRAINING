import type { PracticeLanguage } from '../model/records'
import { addDays } from '../model/history'
import type { PlotRect } from './pitchGraph'

/**
 * [기록] 그래프의 자리 계산 (iOS `HistoryChartView`는 Swift Charts, 웹은 SVG로 그린다).
 * 가로축은 날짜(기간 첫날 0시 ~ 내일 0시), 높이 그래프의 세로축은 반음 눈금(`pitchScale.position`)이다.
 */

export interface DateDomain {
  readonly start: Date
  readonly end: Date
}

/** 왼쪽은 눈금 숫자, 아래는 날짜 자리 */
export function historyPlotRect(width: number, height: number): PlotRect {
  return { x: 36, y: 10, width: Math.max(width - 44, 1), height: Math.max(height - 32, 1) }
}

/** 날짜의 가로 위치 [px] */
export function timeX(date: Date, domain: DateDomain, plot: PlotRect): number {
  const span = domain.end.getTime() - domain.start.getTime()
  return plot.x + ((date.getTime() - domain.start.getTime()) / span) * plot.width
}

/** 기간 안의 날 수 */
export function dayCount(domain: DateDomain): number {
  return Math.max(1, Math.round((domain.end.getTime() - domain.start.getTime()) / 86_400_000))
}

/** 날짜 눈금: 첫날부터 고른 간격으로 많아야 `maxCount`개 (7일이면 매일 못 넣어 이틀마다 등) */
export function dayTicks(domain: DateDomain, maxCount = 5): Date[] {
  const days = dayCount(domain)
  const step = Math.max(1, Math.ceil(days / maxCount))
  const ticks: Date[] = []
  for (let day = 0; day < days; day += step) ticks.push(addDays(domain.start, day))
  return ticks
}

/** 분 눈금: 0부터 보기 좋은 간격으로 (가장 긴 날이 들어가게, 많아야 4개) */
export function minuteTicks(maxMinutes: number): number[] {
  const steps = [1, 2, 5, 10, 15, 30, 60, 120, 240]
  const step = steps.find((s) => maxMinutes / s <= 3) ?? steps[steps.length - 1]
  const top = Math.max(step, Math.ceil(maxMinutes / step) * step)
  return Array.from({ length: top / step + 1 }, (_, i) => i * step)
}

/**
 * 언어별 점 모양 (색은 모두 목소리 색): 한국어 원, 영어 네모, 일본어 세모, 기타 마름모 (iOS와 같다).
 * 색이 아니라 모양으로 나눈다 (색은 역할마다 하나씩만 쓰려고).
 */
export function markerPath(language: PracticeLanguage, x: number, y: number, r: number): string {
  switch (language) {
    case 'ko':
      return `M ${x - r} ${y} a ${r} ${r} 0 1 0 ${2 * r} 0 a ${r} ${r} 0 1 0 ${-2 * r} 0 Z`
    case 'en': {
      const s = r * 0.9
      return `M ${x - s} ${y - s} h ${2 * s} v ${2 * s} h ${-2 * s} Z`
    }
    case 'ja':
      return `M ${x} ${y - r * 1.15} L ${x + r * 1.15} ${y + r * 0.85} L ${x - r * 1.15} ${y + r * 0.85} Z`
    case 'other':
      return `M ${x} ${y - r * 1.3} L ${x + r * 1.1} ${y} L ${x} ${y + r * 1.3} L ${x - r * 1.1} ${y} Z`
  }
}
