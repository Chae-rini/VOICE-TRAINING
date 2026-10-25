/**
 * 녹음 파일 만들기·읽기 도우미. 모두 이 기기 안에서만 한다.
 * - 저장·공유용 WAV (16비트 PCM, 모노): 거의 모든 앱이 열 수 있다. 웹은 브라우저마다 m4a를 만드는 방법이 달라서 WAV를 쓴다.
 * - 불러온 녹음을 하나로 합치기(모노), 너무 긴 녹음은 앞부분만.
 */

/** [s] 불러오는 최대 길이. 더 긴 파일은 앞부분만 쓴다 (iOS와 같다). */
export const MAX_IMPORT_SECONDS = 300

/** 16비트 PCM 모노 WAV 파일 내용 */
export function encodeWav(samples: Float32Array, sampleRate: number): ArrayBuffer {
  const dataBytes = samples.length * 2
  const buffer = new ArrayBuffer(44 + dataBytes)
  const view = new DataView(buffer)
  const text = (offset: number, value: string) => {
    for (let i = 0; i < value.length; i++) view.setUint8(offset + i, value.charCodeAt(i))
  }
  const rate = Math.round(sampleRate)
  text(0, 'RIFF')
  view.setUint32(4, 36 + dataBytes, true)
  text(8, 'WAVE')
  text(12, 'fmt ')
  view.setUint32(16, 16, true) // fmt 조각 크기
  view.setUint16(20, 1, true) // PCM
  view.setUint16(22, 1, true) // 채널 1개
  view.setUint32(24, rate, true)
  view.setUint32(28, rate * 2, true) // 초당 바이트
  view.setUint16(32, 2, true) // 샘플 하나의 바이트
  view.setUint16(34, 16, true) // 비트
  text(36, 'data')
  view.setUint32(40, dataBytes, true)
  for (let i = 0; i < samples.length; i++) {
    // −1~1 밖은 잘라 낸다 (넘치면 소리가 뒤집히지 않게)
    const s = Math.max(-1, Math.min(1, samples[i]))
    view.setInt16(44 + i * 2, s < 0 ? Math.round(s * 0x8000) : Math.round(s * 0x7fff), true)
  }
  return buffer
}

/** 저장할 때 처음 적어 둘 파일 이름. 예: "Ullim-20261025-2012.wav" (녹음한 날짜·시각, iOS ‘파일로 저장’과 같은 모양) */
export function exportFileName(date: Date, extension = 'wav'): string {
  const pad = (n: number) => String(n).padStart(2, '0')
  const stamp = `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}-${pad(date.getHours())}${pad(date.getMinutes())}`
  return `Ullim-${stamp}.${extension}`
}

/** 여러 채널이면 평균해서 하나로 합치고, `maxSeconds`보다 길면 앞부분만 남긴다. */
export function mixToMono(
  channels: readonly Float32Array[],
  sampleRate: number,
  maxSeconds = MAX_IMPORT_SECONDS,
): { samples: Float32Array; wasTruncated: boolean } {
  const length = channels[0]?.length ?? 0
  const kept = Math.min(length, Math.floor(maxSeconds * sampleRate))
  const mono = new Float32Array(kept)
  for (const channel of channels) {
    for (let i = 0; i < kept; i++) mono[i] += channel[i] / channels.length
  }
  return { samples: mono, wasTruncated: length > kept }
}

/** 가장 큰 순간의 크기 (0~1) */
export function peakMagnitude(samples: Float32Array): number {
  let peak = 0
  for (let i = 0; i < samples.length; i++) peak = Math.max(peak, Math.abs(samples[i]))
  return peak
}
