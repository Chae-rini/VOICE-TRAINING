import Foundation

/// 녹음 → 듣기 → 숨 고르기 → 다시 녹음을 정지할 때까지 반복하는 연습 순서표.
/// 녹음은 재생("지금 들어보기")을 누를 때까지 이어지고, 듣기가 끝나면 숨을 고른 뒤 자동으로 다시 녹음한다.
/// 실제 녹음·재생은 AudioInputManager가 하고, 여기서는 "지금 어느 단계인지"만 관리한다.
/// 소리와 떨어져 있어서 단위 테스트로 순서를 확인할 수 있다.
struct PracticeLoop: Equatable {
    enum Phase: Equatable {
        case idle                       // 시작 전, 또는 정지함
        case recording(round: Int)      // round번째 녹음 중. 재생을 누를 때까지 계속
        case listening(round: Int)      // round번째 녹음을 듣는 중
        case countdown(nextRound: Int)  // 다음 녹음 전 숨 고르기
        case replaying                  // 연습하지 않을 때 마지막 녹음(또는 불러온 파일)을 듣는 중
    }

    /// [s] 듣기가 끝나고 다음 녹음까지 숨 고르는 시간. 들려준 뒤 곧바로 다시 녹음되도록 짧게 둔다.
    static let countdownSeconds: TimeInterval = 1
    /// [s] 쉬지 않고 이만큼 연습하면 목을 쉬어 가라고 알린다 (성대 건강). 연습은 멈추지 않는다.
    static let restReminderInterval: TimeInterval = 15 * 60

    private(set) var phase: Phase = .idle

    /// 녹음·듣기·숨 고르기·다시 듣기 중 하나면 true. 이때는 설정을 바꾸지 못하게 잠근다.
    var isActive: Bool {
        phase != .idle
    }

    /// 예: 900초 → "15분 연습했어요. 목을 잠깐 쉬어 주세요."
    static func restMessage(after elapsed: TimeInterval) -> String {
        "\(Int(elapsed / 60))분 연습했어요. 목을 잠깐 쉬어 주세요."
    }

    mutating func start() {
        guard !isActive else { return }
        phase = .recording(round: 1)
    }

    /// 재생을 눌러 녹음을 멈추고 듣기로 넘어간다.
    mutating func recordingFinished() {
        guard case .recording(let round) = phase else { return }
        phase = .listening(round: round)
    }

    /// 듣기가 끝났거나 건너뛰었을 때. 연습 중이면 숨 고르기로, 다시 듣기였으면 처음 상태로 간다.
    mutating func listeningFinished() {
        switch phase {
        case .listening(let round):
            phase = .countdown(nextRound: round + 1)
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
