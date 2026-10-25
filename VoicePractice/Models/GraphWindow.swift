import Foundation

/// 피치 그래프의 가로축에 보일 시간 구간 [s, AudioClock 기준].
/// 가로축 길이는 ‘들려줄 길이’(10초~3분)를 따른다. 오른쪽 끝이 늘 "지금"이고, 곡선과 시간 눈금이 함께 왼쪽으로 흐른다
/// (곡선의 머리가 한자리에 있어서 지금 높이를 읽기 쉽다, 2026-10-25 사용자 요청). 들려줄 길이만큼은 화면에 남는다.
struct GraphWindow: Equatable {
    /// [s] 왼쪽 끝 시각
    let start: TimeInterval
    /// [s] 가로축 길이
    let duration: TimeInterval
    /// [s] 녹음을 시작한 시각. 구간 안에 있으면 ‘녹음 시작’ 세로선을 그리고, 가로축 시간 글자는 여기서부터 센다.
    /// 불러온 파일처럼 없으면 nil (시간은 왼쪽 끝부터 센다).
    var recordingStart: TimeInterval?
    /// 반복 루프에서 몇 번째 녹음인지 (1부터). 2번째부터는 시작선 대신 "2번째" 경계선을 긋는다.
    var round: Int?

    /// 녹음 시작 세로선의 글자: 첫 녹음은 "시작", 반복 루프에서 다시 녹음한 것은 "2번째"처럼.
    var startLabel: String {
        guard let round, round > 1 else { return "시작" }
        return "\(round)번째"
    }

    /// 다시 녹음한 경계선인지 (시작선과 모양을 다르게 그린다)
    var isRoundBoundary: Bool {
        (round ?? 1) > 1
    }

    /// 녹음 시작 세로선을 그릴지: 녹음을 시작한 때가 가로축 안에 있을 때만 (오래 녹음해 흘러가면 왼쪽 밖으로 사라진다)
    var showsStartLine: Bool {
        guard let recordingStart else { return false }
        return recordingStart >= start - 0.01 && recordingStart <= end
    }

    /// [s] 오른쪽 끝 시각
    var end: TimeInterval { start + duration }

    /// 0(왼쪽 끝)~1(오른쪽 끝). 구간 밖이면 0보다 작거나 1보다 크다.
    func position(of time: TimeInterval) -> Double {
        (time - start) / duration
    }

    /// 녹음 중의 구간: 오른쪽 끝이 지금, 왼쪽 끝은 `duration`초 전. 녹음을 시작한 지 `duration`초가 안 됐으면
    /// 시작선 왼쪽은 비어 있다. 이 구간(최근 `duration`초)은 녹음 통이 남겨 두는 소리, 곧 다시 들을 수 있는 구간과 같다.
    static func live(recordingStart: TimeInterval, now: TimeInterval, duration: TimeInterval, round: Int? = nil) -> GraphWindow {
        GraphWindow(start: now - duration, duration: duration, recordingStart: recordingStart, round: round)
    }

    /// 가로축 눈금 간격 후보 [s]. 눈금이 6개 이하가 되는 가장 촘촘한 간격을 쓴다.
    static let tickSteps: [TimeInterval] = [2, 5, 10, 15, 30, 60]

    /// 가로축 눈금 간격 [s]
    var tickStep: TimeInterval {
        Self.tickSteps.first { duration / $0 <= 6 } ?? (duration / 6 / 60).rounded(.up) * 60
    }

    /// 가로축 눈금: 녹음 시작(없으면 왼쪽 끝)부터 `tickStep`마다, 구간 안에 드는 시각과 "1:30" 같은 글자.
    /// 녹음을 시작하기 전(시작선 왼쪽의 빈 곳)에는 눈금을 두지 않는다.
    var ticks: [(time: TimeInterval, label: String)] {
        let origin = recordingStart ?? start
        let step = tickStep
        let first = max(((start - origin) / step - 1e-9).rounded(.up), 0)
        let last = ((end - origin) / step + 1e-9).rounded(.down)
        guard first <= last else { return [] }
        return stride(from: first, through: last, by: 1).map { index in
            (origin + index * step, Self.timeLabel(index * step))
        }
    }

    /// 예: 0 → "0:00", 75 → "1:15"
    static func timeLabel(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

extension RecordedTake {
    /// 이 녹음을 보여 줄 가로축: 녹음이 끝난 때가 오른쪽 끝, 길이는 녹음할 때의 그래프 길이(들려줄 길이).
    /// 녹음하던 화면이 멈춘 모습 그대로라, 멈추거나 다시 들을 때 그래프가 튀지 않는다. 녹음이 더 길면 녹음 길이만큼.
    var graphWindow: GraphWindow {
        let length = max(duration, graphDuration)
        return GraphWindow(start: endTime - length, duration: length, recordingStart: recordingStart, round: round)
    }
}
