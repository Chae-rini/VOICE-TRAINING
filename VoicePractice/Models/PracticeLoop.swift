import Foundation

/// 녹음 → 듣기 → 숨 고르기 → 다시 녹음을 정한 횟수만큼 반복하는 연습 순서표.
/// 실제 녹음·재생은 AudioInputManager가 하고, 여기서는 "지금 어느 단계인지"만 관리한다.
/// 소리와 떨어져 있어서 단위 테스트로 순서를 확인할 수 있다.
struct PracticeLoop: Equatable {
    enum Phase: Equatable {
        case idle                       // 시작 전, 또는 중간에 정지함
        case recording(round: Int)      // round번째 녹음 중
        case listening(round: Int)      // round번째 녹음을 듣는 중
        case countdown(nextRound: Int)  // 다음 녹음 전 숨 고르기
        case replaying                  // 연습이 끝난 뒤 마지막 녹음을 다시 듣는 중
        case finished                   // 정한 횟수를 모두 마침
    }

    /// 성대 건강을 위해 반복은 최대 10회까지만 둔다.
    static let roundRange = 1...10
    static let defaultRounds = 5
    /// [s] 듣기가 끝나고 다음 녹음까지 숨 고르는 시간. 들려준 뒤 곧바로 다시 녹음되도록 짧게 둔다.
    static let countdownSeconds: TimeInterval = 1

    let totalRounds: Int
    private(set) var phase: Phase = .idle

    init(totalRounds: Int = Self.defaultRounds) {
        self.totalRounds = min(max(totalRounds, Self.roundRange.lowerBound), Self.roundRange.upperBound)
    }

    /// 녹음·듣기·숨 고르기·다시 듣기 중 하나면 true. 이때는 설정을 바꾸지 못하게 잠근다.
    var isActive: Bool {
        switch phase {
        case .recording, .listening, .countdown, .replaying: true
        case .idle, .finished: false
        }
    }

    mutating func start() {
        guard !isActive else { return }
        phase = .recording(round: 1)
    }

    mutating func recordingFinished() {
        guard case .recording(let round) = phase else { return }
        phase = .listening(round: round)
    }

    /// 듣기가 끝났거나 건너뛰었을 때. 남은 횟수가 있으면 숨 고르기로, 없으면 끝으로 간다.
    mutating func listeningFinished() {
        switch phase {
        case .listening(let round):
            phase = round < totalRounds ? .countdown(nextRound: round + 1) : .finished
        case .replaying:
            phase = .idle
        default:
            break
        }
    }

    mutating func countdownFinished() {
        guard case .countdown(let round) = phase else { return }
        phase = .recording(round: round)
    }

    mutating func startReplay() {
        guard !isActive else { return }
        phase = .replaying
    }

    mutating func stop() {
        phase = .idle
    }
}
