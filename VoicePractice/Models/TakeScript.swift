import Foundation

/// 녹음 하나가 읽은 대본 (2026-11-03~). 같은 대본을 읽은 녹음끼리 공명 밝기(F2)를 견주는 데 쓴다.
/// 문장 속 F2는 말한 모음에 따라 달라서, 다른 글을 읽은 녹음끼리는 비교가 흐려진다.
nonisolated struct TakeScript: Hashable, Sendable {
    /// `PracticeScript.id` (가져온 내 대본은 `my-`로 시작)
    let id: String
    /// 그때의 제목. 내 대본을 지운 뒤에도 기록에서 이름을 보여 줄 수 있게 같이 남긴다
    let title: String
}

/// [높이] 화면의 대본이 바뀐 시각을 적어 두고, 녹음 하나가 어느 대본을 읽은 것인지 정한다.
/// 반복 루프는 다 들으면 저절로 다시 녹음하므로, 녹음이 시작된 뒤에 다음 대본으로 넘기는 일이 흔하다.
/// 그래서 녹음 내내가 아니라 목소리가 잡힌 동안 화면에 있던 대본으로 정한다.
/// 시각은 피치 점과 같은 시계(`AudioClock`)다.
struct ScriptTimeline {
    /// 목소리가 잡힌 점 중 이 비율 이상이 한 대본을 띄워 둔 동안 나와야 그 대본을 읽은 녹음으로 본다 (임시값).
    /// 대본을 넘기기 앞뒤로 짧게 낸 소리(‘음’ 같은)는 견디고, 두 대본을 이어 읽은 녹음은 빼려고.
    static let minimumShare = 0.9

    private struct Change {
        let time: TimeInterval
        /// nil: 대본이 아닌 문장을 보거나 대본 화면이 사라졌다
        let script: TakeScript?
    }

    private var changes: [Change] = []

    /// 화면의 대본이 바뀌었을 때 부른다. 같은 대본이 다시 오면 아무것도 하지 않는다.
    mutating func show(_ script: TakeScript?, at time: TimeInterval) {
        if let last = changes.last, last.script == script { return }
        changes.append(Change(time: time, script: script))
    }

    /// `time` 앞의 바뀜은 그때 화면에 있던 것 하나만 남기고 잊는다 (오래 연습해도 목록이 길어지지 않게).
    /// 새 녹음을 시작할 때 부른다.
    mutating func forget(before time: TimeInterval) {
        guard let current = changes.lastIndex(where: { $0.time <= time }) else { return }
        changes.removeFirst(current)
    }

    /// 그 시각에 화면에 있던 대본
    func script(at time: TimeInterval) -> TakeScript? {
        changes.last { $0.time <= time }?.script
    }

    /// 녹음의 점 중 목소리가 잡힌 점을 그때 화면의 대본별로 세어, `minimumShare` 이상을 차지한 대본.
    /// 목소리가 없거나, 대본이 섞였거나, 대본이 아닌 것을 보며 말했으면 nil.
    func script(for readings: some Sequence<PitchReading>) -> TakeScript? {
        var counts: [TakeScript?: Int] = [:]
        var voiced = 0
        for reading in readings where reading.frequency != nil {
            counts[script(at: reading.time), default: 0] += 1
            voiced += 1
        }
        guard voiced > 0, let (script, count) = counts.max(by: { $0.value < $1.value }), let script else { return nil }
        return Double(count) / Double(voiced) >= Self.minimumShare ? script : nil
    }
}
