import Foundation

/// 문장 끝 분석을 사람이 읽는 글로 바꾼다 ([높이] 요약 카드, AI 요청문).
/// 웹(`web/src/text/phraseEnding.ts`)에 같은 글이 있다. 한쪽을 고치면 다른 쪽도 고친다.
/// 판정·점수가 아니라 숫자와 방향만 말하고, 끝이 내려가는 것 자체를 나쁘다고 하지 않는다 (원칙 3).
/// 글 속의 기준 숫자(3반음, 0.3초 등)는 `PhraseEndingRules.json`에서 가져온다.
extension PhraseEndingAnalysis {
    /// 요약 한 줄. 예: "문장 끝 11개 중 7개가 3반음 넘게 내려갔어요"
    var headline: String {
        let limit = Self.number(rules.stableMaxDropSemitones)
        guard summary.phraseCount > 0 else {
            return "문장으로 나눌 만큼 목소리가 이어진 곳이 없어요"
        }
        guard summary.fallingOrDroppingCount > 0 else {
            return "문장 끝 \(summary.phraseCount)개 중 \(limit)반음 넘게 내려간 곳은 없어요"
        }
        return "문장 끝 \(summary.phraseCount)개 중 \(summary.fallingOrDroppingCount)개가 \(limit)반음 넘게 내려갔어요"
    }

    /// 요약 한 줄 아래의 숫자들 (해당할 때만). 구절이 없으면 빈 배열.
    var detailLines: [String] {
        guard let mean = summary.meanEndDropSemitones else { return [] }
        let end = Self.number(rules.endWindowSeconds)
        var lines = ["평균 \(Self.dropText(mean))"]
        if let target, let count = summary.endBelowTargetCount {
            lines.append("바닥이 목표 하한(\(Int(target.lowerBound)) Hz) 아래로 내려간 끝: \(count)개")
        }
        if let atEnd = summary.outOfTargetAtEndFraction, let share = summary.endFrameShare {
            lines.append("목표 범위 밖 순간의 \(Self.percent(atEnd))%가 문장 끝 \(end)초에 있어요 (문장 끝은 목소리의 \(Self.percent(share))%)")
        }
        if summary.possibleFryCount > 0 {
            lines.append("끝이 긁혔을 수도 있는 곳: \(summary.possibleFryCount)개 (높이를 잘못 읽었을 수도 있어요)")
        }
        return lines
    }

    /// 안내 문구. 끝이 내려가는 건 자연스럽다는 것을 먼저 말한다.
    var guidance: String {
        target == nil
            ? "끝이 내려가는 건 자연스러워요. \(Self.number(rules.stableMaxDropSemitones))반음 안쪽으로만 내려가게 해 보세요."
            : "끝이 내려가는 건 자연스러워요. 바닥이 목표 하한 아래로 내려가지 않게만 해 보세요."
    }

    /// AI 요청문에 넣을 줄들. 구절이 없으면 빈 배열.
    var requestLines: [String] {
        guard let mean = summary.meanEndDropSemitones, let fraction = summary.fallingOrDroppingFraction else { return [] }
        let silence = Self.number(rules.phraseBreakSilenceSeconds)
        let end = Self.number(rules.endWindowSeconds)
        let limit = Self.number(rules.stableMaxDropSemitones)
        var lines = [
            "문장 끝 (무성음 \(silence)초 이상에서 구절을 나누고, 구절마다 마지막 \(end)초를 구절 전체와 비교)",
            "- 구절 수: \(summary.phraseCount)개",
            "- 평균 하강 폭: \(String(format: "%.1f", mean))반음 (구절 중앙값 → 마지막 \(end)초 중앙값, +면 내려감)",
            "- \(limit)반음 넘게 내려간 구절: \(summary.fallingOrDroppingCount)개 (\(Self.percent(fraction))%)",
        ]
        if let count = summary.endBelowTargetCount {
            lines.append("- 끝 바닥(마지막 \(end)초의 아래 \(Self.percent(rules.endFloorPercentile))%)이 목표 하한 아래인 구절: \(count)개")
        }
        if let atEnd = summary.outOfTargetAtEndFraction, let share = summary.endFrameShare {
            lines.append("- 목표 범위 밖 순간 중 문장 끝 \(end)초에 있던 비율: \(Self.percent(atEnd))% (문장 끝은 목소리가 잡힌 시간의 \(Self.percent(share))%)")
        }
        lines.append("- 끝에 아주 낮은 높이가 이어진 구절(긁히는 소리 가능성, 높이 검출 오류일 수도 있음): \(summary.possibleFryCount)개")
        lines.append(target == nil
            ? "한국어 평서문은 끝이 내려가는 게 자연스러우니, 평평하게가 아니라 하강 폭 \(limit)반음 이내인지로 봐 주세요."
            : "한국어 평서문은 끝이 내려가는 게 자연스러우니, 평평하게가 아니라 하강 폭 \(limit)반음 이내, 끝 바닥이 목표 하한 아래로 내려가지 않는지로 봐 주세요.")
        return lines
    }

    /// 예: 2.4 → "2.4반음 내려감", −1.2 → "1.2반음 올라감", 0.02 → "거의 그대로"
    static func dropText(_ drop: Double) -> String {
        let size = String(format: "%.1f", abs(drop))
        if size == "0.0" { return "거의 그대로" }
        return drop > 0 ? "\(size)반음 내려감" : "\(size)반음 올라감"
    }

    /// 0~1 → 반올림한 백분율
    static func percent(_ fraction: Double) -> Int {
        Int((fraction * 100).rounded())
    }

    /// 기준값을 글에 넣을 때: 3 → "3", 0.25 → "0.25"
    static func number(_ value: Double) -> String {
        String(format: "%g", value)
    }
}

extension PhraseEnding {
    /// 구절 중앙값 → 끝 중앙값. 예: "182 → 158 Hz"
    var pitchLine: String {
        "\(Int(phraseMedian.rounded())) → \(Int(endMedian.rounded())) Hz"
    }

    /// 예: "2.4반음 내려감"
    var dropLabel: String {
        PhraseEndingAnalysis.dropText(endDropSemitones)
    }

    /// 눈여겨볼 점 (해당할 때만). 예: ["바닥 150 Hz · 목표 하한 아래", "긁혔을 수도 있어요"]
    var notes: [String] {
        var notes: [String] = []
        if endBelowTarget == true {
            notes.append("바닥 \(Int(endFloor.rounded())) Hz · 목표 하한 아래")
        }
        if possibleFry {
            notes.append("긁혔을 수도 있어요")
        }
        return notes
    }
}

extension PhraseEndType {
    /// 화면에 쓰는 이름
    var label: String {
        switch self {
        case .rise: "올라감"
        case .stable: "안정"
        case .falling: "내려감"
        case .dropping: "크게 내려감"
        }
    }
}
