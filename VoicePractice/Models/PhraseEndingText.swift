import Foundation

/// 문장 끝 분석을 사람이 읽는 글로 바꾼다 ([높이] 요약 카드, AI 요청문).
/// 웹(`web/src/text/phraseEnding.ts`)에 같은 글이 있다. 한쪽을 고치면 다른 쪽도 고친다.
/// 판정·점수가 아니라 숫자와 방향만 말하고, 끝이 내려가는 것 자체를 나쁘다고 하지 않는다 (원칙 3).
/// 글 속의 기준 숫자(3반음, 0.3초 등)는 `PhraseEndingRules.json`에서 가져온다.
extension PhraseEndingAnalysis {
    /// 요약 한 줄. 예: "문장 끝 11개 중 7개가 3반음 넘게 내려갔어요"
    var headline: String {
        summary.headline(rules: rules)
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
        summary.requestLines(rules: rules)
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

/// 문장 끝 숫자만으로 쓰는 글. 녹음 하나의 분석(위)과 기록에 남은 숫자(연습 기록의 녹음마다·남긴 녹음, 2026-10-30~)가 같이 쓴다.
/// 기록에는 구절별 목록과 목표 범위 없이 숫자만 남는다. 목표 범위가 있었는지는 ‘끝 바닥이 목표 하한 아래인 구절’ 칸이 있는지로 안다.
/// 글 속의 기준 숫자는 지금의 `PhraseEndingRules.json` 값이다.
extension PhraseEndingSummary {
    /// 요약 한 줄. 예: "문장 끝 11개 중 7개가 3반음 넘게 내려갔어요"
    func headline(rules: PhraseEndingRules) -> String {
        let limit = PhraseEndingAnalysis.number(rules.stableMaxDropSemitones)
        guard phraseCount > 0 else {
            return "문장으로 나눌 만큼 목소리가 이어진 곳이 없어요"
        }
        guard fallingOrDroppingCount > 0 else {
            return "문장 끝 \(phraseCount)개 중 \(limit)반음 넘게 내려간 곳은 없어요"
        }
        return "문장 끝 \(phraseCount)개 중 \(fallingOrDroppingCount)개가 \(limit)반음 넘게 내려갔어요"
    }

    /// 녹음마다 줄에 붙이는 짧은 말. 예: "문장 끝 11개 중 7개 3반음 넘게 내려감, 평균 2.4반음 내려감". 구절이 없으면 nil
    func shortPhrase(rules: PhraseEndingRules) -> String? {
        guard let mean = meanEndDropSemitones, phraseCount > 0 else { return nil }
        let limit = PhraseEndingAnalysis.number(rules.stableMaxDropSemitones)
        return "문장 끝 \(phraseCount)개 중 \(fallingOrDroppingCount)개 \(limit)반음 넘게 내려감, 평균 \(PhraseEndingAnalysis.dropText(mean))"
    }

    /// AI 요청문에 넣을 줄들. 구절이 없으면 빈 배열.
    /// `combinedTakeCount`: 녹음 여러 개를 합친 요약이면 그 수 (연습 기록의 요청문). 머리줄에 합쳤다고 밝힌다.
    func requestLines(rules: PhraseEndingRules, combinedTakeCount: Int? = nil) -> [String] {
        guard let mean = meanEndDropSemitones, let fraction = fallingOrDroppingFraction else { return [] }
        let silence = PhraseEndingAnalysis.number(rules.phraseBreakSilenceSeconds)
        let end = PhraseEndingAnalysis.number(rules.endWindowSeconds)
        let limit = PhraseEndingAnalysis.number(rules.stableMaxDropSemitones)
        let percent = PhraseEndingAnalysis.percent
        let scope = combinedTakeCount.map { "녹음 \($0)개를 합쳐서, " } ?? ""
        var lines = [
            "문장 끝 (\(scope)무성음 \(silence)초 이상에서 구절을 나누고, 구절마다 마지막 \(end)초를 구절 전체와 비교)",
            "- 구절 수: \(phraseCount)개",
            "- 평균 하강 폭: \(String(format: "%.1f", mean))반음 (구절 중앙값 → 마지막 \(end)초 중앙값, +면 내려감)",
            "- \(limit)반음 넘게 내려간 구절: \(fallingOrDroppingCount)개 (\(percent(fraction))%)",
        ]
        if let count = endBelowTargetCount {
            lines.append("- 끝 바닥(마지막 \(end)초의 아래 \(percent(rules.endFloorPercentile))%)이 목표 하한 아래인 구절: \(count)개")
        }
        if let atEnd = outOfTargetAtEndFraction, let share = endFrameShare {
            lines.append("- 목표 범위 밖 순간 중 문장 끝 \(end)초에 있던 비율: \(percent(atEnd))% (문장 끝은 목소리가 잡힌 시간의 \(percent(share))%)")
        }
        lines.append("- 끝에 아주 낮은 높이가 이어진 구절(긁히는 소리 가능성, 높이 검출 오류일 수도 있음): \(possibleFryCount)개")
        lines.append(endBelowTargetCount == nil
            ? "한국어 평서문은 끝이 내려가는 게 자연스러우니, 평평하게가 아니라 하강 폭 \(limit)반음 이내인지로 봐 주세요."
            : "한국어 평서문은 끝이 내려가는 게 자연스러우니, 평평하게가 아니라 하강 폭 \(limit)반음 이내, 끝 바닥이 목표 하한 아래로 내려가지 않는지로 봐 주세요.")
        return lines
    }

    /// 녹음 여러 개를 하나로 합친다 (연습 기록 전체). 구절 수·개수는 더하고, 평균 하강 폭은 구절 수로 가중 평균한다.
    /// 목표 밖·문장 끝 비율 두 개는 녹음마다 분모(프레임 수)가 남아 있지 않아 합칠 수 없으므로 비운다.
    /// ‘끝 바닥이 목표 하한 아래’는 목표 범위가 있던 녹음만 더한다 (하나도 없으면 nil). 합칠 것이 없으면 nil.
    static func combined(_ summaries: [PhraseEndingSummary]) -> PhraseEndingSummary? {
        guard !summaries.isEmpty else { return nil }
        let phrases = summaries.map(\.phraseCount).reduce(0, +)
        let falling = summaries.map(\.fallingOrDroppingCount).reduce(0, +)
        let dropSum = summaries.compactMap { summary in summary.meanEndDropSemitones.map { $0 * Double(summary.phraseCount) } }
            .reduce(0, +)
        let belowTarget = summaries.compactMap(\.endBelowTargetCount)
        return PhraseEndingSummary(
            phraseCount: phrases,
            meanEndDropSemitones: phrases > 0 ? dropSum / Double(phrases) : nil,
            fallingOrDroppingCount: falling,
            fallingOrDroppingFraction: phrases > 0 ? Double(falling) / Double(phrases) : nil,
            endBelowTargetCount: belowTarget.isEmpty ? nil : belowTarget.reduce(0, +),
            possibleFryCount: summaries.map(\.possibleFryCount).reduce(0, +),
            outOfTargetAtEndFraction: nil,
            endFrameShare: nil
        )
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
