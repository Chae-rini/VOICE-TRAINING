/**
 * F1이 불확실한지 (iOS `Models/VowelSpace.swift`): 목소리가 높고(F0 ≥ 200 Hz) F1이 2.5×F0보다 낮으면
 * 가까운 배음으로 끌렸을 수 있다. 합성 모음 검증에서 F0 200 Hz 이상, F1이 낮은 모음에서 최대 20~36% 오차를 본 것을 바탕으로 정했다.
 * [모음] 탭은 W3 다음에 옮긴다. 지금은 공명 밝기 막대가 쓰는 이 규칙만 있다.
 */
export function isF1Uncertain(f1: number, f0: number): boolean {
  return f0 >= 200 && f1 < 2.5 * f0
}
