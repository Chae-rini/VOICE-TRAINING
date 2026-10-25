import { encodeWav, exportFileName } from '../audio/wav'
import type { PitchSummary } from '../dsp/pitchSummary'
import type { RecordedTake } from './take'

/**
 * 마지막 녹음 내보내기: 파일로 저장(WAV 내려받기), AI에게 피드백 받기(브라우저 공유 창), 요약 복사.
 * 앱은 인터넷으로 아무것도 보내지 않는다. 보낼 곳·저장할 곳은 사용자가 고른다 (원칙 2).
 */

/** 원래 소리(키우기 전)로 만든 WAV 파일 */
export function takeWavFile(take: RecordedTake): File {
  return new File([encodeWav(take.samples, take.sampleRate)], exportFileName(take.recordedAt), { type: 'audio/wav' })
}

/** WAV 파일을 이 기기에 내려받는다 (브라우저에 따라 저장할 곳을 묻거나 다운로드 폴더에 둔다). */
export function downloadTake(take: RecordedTake): void {
  const file = takeWavFile(take)
  const url = URL.createObjectURL(file)
  const link = document.createElement('a')
  link.href = url
  link.download = file.name
  document.body.append(link)
  link.click()
  link.remove()
  // 내려받기가 시작될 시간을 두고 치운다
  setTimeout(() => URL.revokeObjectURL(url), 60_000)
}

export async function copyText(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    return false
  }
}

export type ShareResult = 'shared' | 'cancelled' | 'copied' | 'failed'

/**
 * 피드백 요청문(원하면 녹음 파일도)을 브라우저 공유 창에 넘긴다. 받을 앱은 사용자가 고른다.
 * 공유 창이 없는 브라우저(컴퓨터의 일부 브라우저)이거나 파일을 넘길 수 없으면 요청문을 복사한다.
 */
export async function shareFeedback(take: RecordedTake, summary: PitchSummary, includesAudio: boolean): Promise<ShareResult> {
  const file = includesAudio ? takeWavFile(take) : null
  const canShareFile = file !== null && typeof navigator.canShare === 'function' && navigator.canShare({ files: [file] })
  const text = summary.feedbackRequest(take.title, canShareFile)
  if (typeof navigator.share === 'function' && (file === null || canShareFile)) {
    try {
      await navigator.share(canShareFile && file !== null ? { text, files: [file] } : { text })
      return 'shared'
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') return 'cancelled'
    }
  }
  return (await copyText(text)) ? 'copied' : 'failed'
}
