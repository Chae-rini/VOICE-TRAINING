/**
 * 녹음 → 듣기 → 숨 고르기 → 다시 녹음을 정지할 때까지 반복하는 연습 순서표 (iOS `PracticeLoop`).
 * 녹음은 "지금 들어보기"를 누를 때까지 이어지고, 듣기가 끝나면 숨을 고른 뒤 자동으로 다시 녹음한다.
 * 실제 녹음·재생은 세션이 하고, 여기서는 "지금 어느 단계인지"만 관리한다 (소리와 떨어져 있어 테스트로 확인한다).
 */
export type LoopPhase =
  | { readonly kind: 'idle' } // 시작 전, 또는 정지함
  | { readonly kind: 'recording'; readonly round: number } // round번째 녹음 중. 들어보기를 누를 때까지 계속
  | { readonly kind: 'listening'; readonly round: number } // round번째 녹음을 듣는 중
  | { readonly kind: 'countdown'; readonly nextRound: number } // 다음 녹음 전 숨 고르기
  | { readonly kind: 'replaying' } // 연습하지 않을 때 마지막 녹음(또는 불러온 파일)을 듣는 중
  | { readonly kind: 'measuring' } // 내 목소리 재기 (10초, 끝나면 처음 상태로)

/** [s] 듣기가 끝나고 다음 녹음까지 숨 고르는 시간. 들려준 뒤 곧바로 다시 녹음되도록 짧게 둔다. */
export const COUNTDOWN_SECONDS = 1

const IDLE: LoopPhase = { kind: 'idle' }

export class PracticeLoop {
  phase: LoopPhase = IDLE

  /** 녹음·듣기·숨 고르기·다시 듣기·목소리 재기 중 하나면 true. 이때는 설정을 바꾸지 못하게 잠근다. */
  get isActive(): boolean {
    return this.phase.kind !== 'idle'
  }

  start(): void {
    if (this.isActive) return
    this.phase = { kind: 'recording', round: 1 }
  }

  /** 들어보기를 눌러 녹음을 멈추고 듣기로 넘어간다. */
  recordingFinished(): void {
    if (this.phase.kind !== 'recording') return
    this.phase = { kind: 'listening', round: this.phase.round }
  }

  /** 듣기가 끝났거나 건너뛰었을 때. 연습 중이면 숨 고르기로, 다시 듣기였으면 처음 상태로 간다. */
  listeningFinished(): void {
    if (this.phase.kind === 'listening') this.phase = { kind: 'countdown', nextRound: this.phase.round + 1 }
    else if (this.phase.kind === 'replaying') this.phase = IDLE
  }

  countdownFinished(): void {
    if (this.phase.kind !== 'countdown') return
    this.phase = { kind: 'recording', round: this.phase.nextRound }
  }

  startReplay(): void {
    if (this.isActive) return
    this.phase = { kind: 'replaying' }
  }

  startMeasuring(): void {
    if (this.isActive) return
    this.phase = { kind: 'measuring' }
  }

  stop(): void {
    this.phase = IDLE
  }
}
