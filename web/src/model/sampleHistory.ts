import { PitchSummary } from '../dsp/pitchSummary'
import type { Range } from '../dsp/range'
import { sessionRecord, type TakeSummary } from '../practice/sessionLog'
import { EMPTY_RECORDS, type RecordsData } from '../storage/archive'
import { addDays, startOfDay } from './history'
import { newRecordId, type BaselineRecord, type PracticeLanguage, type SessionRecord } from './records'

/**
 * 개발용 가짜 연습 기록 (iOS `Models/SampleHistory.swift`와 같은 규칙). 미리보기 브라우저는 마이크를 막아서 진짜 기록을 만들기 어려워,
 * [기록] 화면을 확인할 때만 쓴다. 개발 서버에서 주소 끝에 `?seed`를 붙이면, 기록 폴더에 연결돼 있지 않고 연습 기록이 없을 때만 넣는다.
 * 배포 빌드에는 들어가지 않는다 (`App.svelte`가 개발 서버에서만 불러온다).
 */
export function sampleRecords(now: Date, target: Range | null): RecordsData {
  const today = startOfDay(now)
  const sessions: SessionRecord[] = []
  const atHour = (day: Date, hour: number) => new Date(day.getTime() + hour * 3_600_000)

  // 40일 전부터 오늘까지, 사흘에 하루는 쉰다. 나흘마다 영어 발표 연습, 닷새마다 아침에도 한 번.
  // 공명 밝기(F2)는 30일 전부터만 남긴다 (그 전 연습은 이 값을 저장하기 전의 기록처럼). 영어는 모음이 달라 F2가 다르게 나온다.
  for (let daysAgo = 40; daysAgo >= 0; daysAgo--) {
    if (daysAgo % 3 === 1) continue
    const day = addDays(today, -daysAgo)
    const language: PracticeLanguage = daysAgo % 4 === 0 ? 'en' : 'ko'
    const median = 150 + (40 - daysAgo) * 0.4 + (language === 'en' ? 12 : 0) + Math.sin(daysAgo) * 4
    const f2 = daysAgo > 30 ? null : 1450 + (30 - daysAgo) * 3 + (language === 'en' ? -90 : 0) + Math.cos(daysAgo) * 40
    sessions.push(sample(atHour(day, 20), 6 + (daysAgo % 5) * 3, median, 2 + (daysAgo % 4), language, target, f2))
    if (daysAgo % 5 === 0) sessions.push(sample(atHour(day, 8), 4, median - 6, 1, 'ko', target, f2 === null ? null : f2 - 30))
  }
  const baselineHistory: BaselineRecord[] = [38, 20, 3].map((daysAgo) => {
    const median = 148 + (40 - daysAgo) * 0.3
    return {
      id: newRecordId(),
      measuredAt: atHour(addDays(today, -daysAgo), 19).toISOString(),
      median,
      low: median - 18,
      high: median + 22,
      f2: daysAgo > 30 ? null : 1480 + (30 - daysAgo) * 2,
    }
  })
  return { ...EMPTY_RECORDS, sessions, baselineHistory }
}

/** `count`개의 높이를 `center` ± `half` 사이에 고르게 */
function spread(center: number, half: number, count: number): number[] {
  return Array.from({ length: count }, (_, i) => center - half + (2 * half * i) / (count - 1))
}

function sample(
  start: Date,
  minutes: number,
  median: number,
  takes: number,
  language: PracticeLanguage,
  target: Range | null,
  f2: number | null,
): SessionRecord {
  const duration = minutes * 60
  // 중앙값 ±20 Hz에 고르게 퍼진 높이 → 아래 10%·위 10%는 중앙값 ±16 Hz
  const pitch = PitchSummary.fromVoiced(spread(median, 20, 100), duration * 0.4, duration, target)!
  // 녹음마다: 1분씩, 녹음할수록 중앙값이 3 Hz씩 오른다
  const takeSummaries: TakeSummary[] = Array.from({ length: takes }, (_, i) => ({
    round: i + 1,
    endedAt: new Date(start.getTime() + (i + 1) * 90_000),
    pitch: PitchSummary.fromVoiced(spread(median - 4 + i * 3, 15, 50), 25, 60, target)!,
  }))
  return sessionRecord({
    startedAt: start,
    endedAt: new Date(start.getTime() + duration * 1000),
    takeCount: takes,
    language,
    pitch,
    takes: takeSummaries,
    f2Median: f2,
  })
}
