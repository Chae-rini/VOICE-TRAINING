/**
 * 녹음하는 동안 들어온 소리 중 최근 `keepSeconds`초만 메모리에 남긴다. 파일로 저장하지 않는다 (iOS `TakeRecorder`).
 * 고리(ring) 모양 버퍼라서, 가득 차면 가장 오래된 소리 자리에 새 소리를 덮어쓴다. 분석 스레드(Web Worker) 안에서 쓴다.
 */
export class TakeRecorder {
  /** [샘플] 보관할 최대 길이. 넘치면 오래된 소리부터 버린다 */
  readonly capacity: number
  private readonly ring: Float32Array
  /** 다음 샘플을 쓸 자리 */
  private writeIndex = 0
  /** 지금 보관 중인 샘플 수 (최대 capacity) */
  private count = 0
  /** [s] 마지막 샘플 바로 뒤의 시각 */
  private endTime: number | null = null

  constructor(
    readonly sampleRate: number,
    keepSeconds: number,
  ) {
    this.capacity = Math.max(Math.trunc(sampleRate * keepSeconds), 1)
    // 3분이면 약 35 MB를 미리 잡는다 (iOS와 같다).
    this.ring = new Float32Array(this.capacity)
  }

  /** `time`은 이 조각 첫 샘플의 시각 [s]. */
  append(chunk: Float32Array, time: number): void {
    const { capacity, ring } = this
    // 조각 하나가 통째로 보관 길이보다 길면 끝부분만 남긴다.
    const kept = chunk.length > capacity ? chunk.subarray(chunk.length - capacity) : chunk
    // 고리의 끝까지 쓰고, 남은 것은 맨 앞으로 돌아가 이어 쓴다.
    const firstPart = Math.min(kept.length, capacity - this.writeIndex)
    ring.set(kept.subarray(0, firstPart), this.writeIndex)
    ring.set(kept.subarray(firstPart), 0)
    this.writeIndex = (this.writeIndex + kept.length) % capacity
    this.count = Math.min(this.count + kept.length, capacity)
    this.endTime = time + chunk.length / this.sampleRate
  }

  get sampleCount(): number {
    return this.count
  }

  /** 보관 중인 첫 샘플의 시각 [s]. 아직 아무것도 녹음되지 않았으면 null. 조각은 빈틈없이 이어지므로 끝에서 거슬러 구한다. */
  get startTime(): number | null {
    return this.endTime === null ? null : this.endTime - this.count / this.sampleRate
  }

  /** 보관 중인 소리를 오래된 것부터 순서대로 꺼낸다 (새 배열). */
  orderedSamples(): Float32Array {
    const { capacity, count, ring } = this
    const start = (this.writeIndex - count + capacity) % capacity
    const result = new Float32Array(count)
    if (start + count <= capacity) {
      result.set(ring.subarray(start, start + count))
    } else {
      result.set(ring.subarray(start))
      result.set(ring.subarray(0, start + count - capacity), capacity - start)
    }
    return result
  }
}
