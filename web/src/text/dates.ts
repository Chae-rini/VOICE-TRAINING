/** 화면에 쓰는 날짜·시각 글자 (이 기기의 시간대, 한국어) */

const dayTime = new Intl.DateTimeFormat('ko-KR', { month: 'long', day: 'numeric', weekday: 'short', hour: 'numeric', minute: '2-digit' })
const dayOnly = new Intl.DateTimeFormat('ko-KR', { month: 'long', day: 'numeric', weekday: 'short' })
const dayTimeNoWeekday = new Intl.DateTimeFormat('ko-KR', { month: 'long', day: 'numeric', hour: 'numeric', minute: '2-digit' })

/** 예: 10월 25일 (일) 오후 8:12 */
export function formatDayTime(date: Date): string {
  return dayTime.format(date)
}

/** 예: 2026년 10월 25일 (일) 오후 8:12 (연도를 넣으면 요일 괄호가 빠져서 직접 붙인다) */
export function formatFullDateTime(date: Date): string {
  return `${date.getFullYear()}년 ${dayTime.format(date)}`
}

/** 예: 10월 25일 (일) */
export function formatDay(date: Date): string {
  return dayOnly.format(date)
}

/** 예: 10월 25일 오후 8:12 */
export function formatShortDateTime(date: Date): string {
  return dayTimeNoWeekday.format(date)
}

/** 그래프 가로축 눈금. 예: 10/25 */
export function formatAxisDay(date: Date): string {
  return `${date.getMonth() + 1}/${date.getDate()}`
}
