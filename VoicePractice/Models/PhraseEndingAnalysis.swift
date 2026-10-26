import Foundation

/// 구절별 문장 끝 분석의 기준값. 값은 `PhraseEndingRules.json` 한 파일에 있고,
/// 웹(`web/src/dsp/phraseEnding.ts`)도 같은 파일을 읽는다. 각 값의 뜻은 그 파일의 `notes`에 적어 두었다.
/// 시간은 [s], 높이는 [Hz], 하강 폭은 [반음]이다.
struct PhraseEndingRules: Codable, Equatable {
    let phraseBreakSilenceSeconds: Double
    let minimumPhraseVoicedSeconds: Double
    let endWindowSeconds: Double
    let endFloorPercentile: Double
    let riseMaxDropSemitones: Double
    let stableMaxDropSemitones: Double
    let fallingMaxDropSemitones: Double
    let fryFloorHz: Double
    let fryMedianRatio: Double
    let fryMinimumFrames: Int
    let fryReferenceFrameSeconds: Double

    /// 앱에 들어 있는 기준값. 파일이 없거나 형식이 틀리면 nil이다 (테스트가 잡아낸다).
    static let standard: PhraseEndingRules? = load(from: .main)

    static func load(from bundle: Bundle) -> PhraseEndingRules? {
        guard let url = bundle.url(forResource: "PhraseEndingRules", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(PhraseEndingRules.self, from: data)
    }

    /// 긁히는 소리 가능성으로 볼 최소 연속 프레임 수를 실제 프레임 간격으로 환산한다.
    /// 기준은 10 ms 간격의 5프레임(= 50 ms)이다. 48 kHz의 21.3 ms 간격이면 ⌈50 / 21.3⌉ = 3프레임.
    /// 올림이라 기준 시간보다 짧은 연속은 세지 않는다.
    func fryMinimumRun(frameInterval: TimeInterval) -> Int {
        let duration = Double(fryMinimumFrames) * fryReferenceFrameSeconds  // [s]
        return max(1, Int((duration / frameInterval - PhraseEndingAnalysis.tolerance).rounded(.up)))
    }
}

/// 문장 끝이 어떻게 움직였는지. 하강 폭 [반음] = 12·log₂(구절 중앙값 ÷ 끝 중앙값)으로 가른다.
enum PhraseEndType: String, Codable {
    /// 끝이 올라감 (질문 억양). 감점하지 않는다
    case rise
    /// 하강 폭이 작다 (기본 3반음 이내)
    case stable
    /// 조금 크게 내려감 (기본 3~5반음)
    case falling
    /// 크게 내려감 (기본 5반음 넘게)
    case dropping

    init(dropSemitones drop: Double, rules: PhraseEndingRules) {
        if drop <= rules.riseMaxDropSemitones {
            self = .rise
        } else if drop <= rules.stableMaxDropSemitones {
            self = .stable
        } else if drop <= rules.fallingMaxDropSemitones {
            self = .falling
        } else {
            self = .dropping
        }
    }
}

/// 구절 하나의 문장 끝.
struct PhraseEnding: Equatable {
    /// [s] 구절의 첫 유성 프레임 시각
    let startTime: TimeInterval
    /// [s] 구절의 마지막 유성 프레임 시각
    let endTime: TimeInterval
    /// 구절 전체의 유성 프레임 수
    let voicedFrameCount: Int
    /// 문장 끝(마지막 `endWindowSeconds`) 안의 유성 프레임 수
    let endFrameCount: Int
    /// [Hz] 구절 전체 유성 프레임의 중앙값
    let phraseMedian: Double
    /// [Hz] 문장 끝 유성 프레임의 중앙값
    let endMedian: Double
    /// [Hz] 문장 끝의 바닥 (10번째 백분위수). 최솟값 대신 써서 검출 오류로 튀는 값을 뺀다
    let endFloor: Double
    /// [반음] 12·log₂(phraseMedian ÷ endMedian). +면 끝이 내려갔다
    let endDropSemitones: Double
    /// 끝 바닥이 목표 하한보다 낮은지. 목표 범위가 없으면 nil
    let endBelowTarget: Bool?
    let endType: PhraseEndType
    /// 문장 끝에 아주 낮은 프레임이 이어졌는지. 긁히는 소리(보컬 프라이)일 수도, 옥타브 오류일 수도 있다
    let possibleFry: Bool
}

/// 녹음 한 번의 문장 끝 요약.
struct PhraseEndingSummary: Equatable {
    let phraseCount: Int
    /// [반음] 구절마다의 하강 폭 평균. 구절이 없으면 nil
    let meanEndDropSemitones: Double?
    /// ‘falling’·‘dropping’ 구절 수
    let fallingOrDroppingCount: Int
    /// 0~1. ‘falling’·‘dropping’ 구절의 비율. 구절이 없으면 nil
    let fallingOrDroppingFraction: Double?
    /// 끝 바닥이 목표 하한 아래인 구절 수. 목표 범위가 없으면 nil
    let endBelowTargetCount: Int?
    /// 긁히는 소리 가능성이 있는 구절 수
    let possibleFryCount: Int
    /// 0~1. 목표 범위 밖 유성 프레임 중 문장 끝에 든 비율. 목표 범위가 없거나 밖 프레임이 없으면 nil
    let outOfTargetAtEndFraction: Double?
    /// 0~1. 전체 유성 프레임 중 문장 끝에 든 비율. 위 비율과 견줄 기준이다
    /// (문장 끝이 원래 전체의 20%인데 목표 밖의 70%가 거기 있으면 끝에 몰려 있는 것). 유성 프레임이 없으면 nil
    let endFrameShare: Double?
}

/// 녹음 한 번을 구절로 나누고, 구절마다 문장 끝이 얼마나 내려갔는지 잰다.
/// 입력은 피치 점(무성음은 frequency == nil)과 사용자가 정한 목표 범위뿐이다. 화면과 상관없는 계산만 한다.
/// 웹(`web/src/dsp/phraseEnding.ts`)에 같은 계산이 줄 단위로 옮겨져 있다. 한쪽을 고치면 다른 쪽도 고친다.
struct PhraseEndingAnalysis: Equatable {
    /// [s] 시각을 비교할 때의 여유. 부동소수 반올림 때문에 경계에 딱 걸친 프레임이 빠지지 않게 한다
    static let tolerance = 1e-9

    /// 계산에 쓴 기준값과 목표 범위 (화면 글·요청문이 같은 숫자를 쓰게 함께 둔다)
    let rules: PhraseEndingRules
    let target: ClosedRange<Double>?
    /// [s] 피치 점 사이 간격 (48 kHz에서 약 21.3 ms, 샘플레이트에 따라 다르다)
    let frameInterval: TimeInterval
    let phrases: [PhraseEnding]
    let summary: PhraseEndingSummary

    private struct Frame {
        let time: TimeInterval  // [s]
        let frequency: Double   // [Hz]
    }

    /// `readings`는 시간 순서여야 한다 (녹음 묶음의 점은 늘 그렇다).
    init(readings: [PitchReading], target: ClosedRange<Double>?, rules: PhraseEndingRules) {
        let interval = Self.frameInterval(of: readings)
        let voiced = readings.compactMap { reading in
            reading.frequency.map { Frame(time: reading.time, frequency: $0) }
        }

        // 1. 구절 나누기: 이웃한 유성 프레임 사이의 무성음 길이(시각 차이 − 한 칸)가 기준 이상이면 끊는다.
        var groups: [[Frame]] = []
        for frame in voiced {
            if let last = groups.last?.last,
               frame.time - last.time - interval < rules.phraseBreakSilenceSeconds - Self.tolerance {
                groups[groups.count - 1].append(frame)
            } else {
                groups.append([frame])
            }
        }

        // 2. 구절마다 문장 끝 재기. 유성음이 너무 짧은 구절은 버린다.
        var phrases: [PhraseEnding] = []
        var endFrames = 0
        var outOfTargetAtEnd = 0
        for group in groups
        where Double(group.count) * interval >= rules.minimumPhraseVoicedSeconds - Self.tolerance {
            let lastTime = group[group.count - 1].time
            let ending = group.filter { $0.time >= lastTime - rules.endWindowSeconds - Self.tolerance }
            let endSorted = ending.map(\.frequency).sorted()

            let phraseMedian = PitchSummary.percentile(group.map(\.frequency).sorted(), 0.5)
            let endMedian = PitchSummary.percentile(endSorted, 0.5)
            let endFloor = PitchSummary.percentile(endSorted, rules.endFloorPercentile)
            let drop = PitchScale.semitones(from: endMedian, to: phraseMedian)
            let fryCeiling = max(rules.fryFloorHz, phraseMedian * rules.fryMedianRatio)  // [Hz]
            let fryRun = Self.longestRun(of: ending, below: fryCeiling, interval: interval)

            phrases.append(PhraseEnding(
                startTime: group[0].time,
                endTime: lastTime,
                voicedFrameCount: group.count,
                endFrameCount: ending.count,
                phraseMedian: phraseMedian,
                endMedian: endMedian,
                endFloor: endFloor,
                endDropSemitones: drop,
                endBelowTarget: target.map { endFloor < $0.lowerBound },
                endType: PhraseEndType(dropSemitones: drop, rules: rules),
                possibleFry: fryRun >= rules.fryMinimumRun(frameInterval: interval)
            ))
            endFrames += ending.count
            if let target {
                outOfTargetAtEnd += ending.filter { !target.contains($0.frequency) }.count
            }
        }

        // 3. 녹음 전체 요약. 목표 밖 프레임은 버린 구절까지 포함한 전체 유성 프레임에서 센다 (요약 카드의 ‘목표 범위 안’과 같은 기준).
        let outOfTarget = target.map { target in voiced.filter { !target.contains($0.frequency) }.count }
        let fallingOrDropping = phrases.filter { $0.endType == .falling || $0.endType == .dropping }.count
        let count = Double(phrases.count)

        self.rules = rules
        self.target = target
        frameInterval = interval
        self.phrases = phrases
        summary = PhraseEndingSummary(
            phraseCount: phrases.count,
            meanEndDropSemitones: phrases.isEmpty ? nil : phrases.map(\.endDropSemitones).reduce(0, +) / count,
            fallingOrDroppingCount: fallingOrDropping,
            fallingOrDroppingFraction: phrases.isEmpty ? nil : Double(fallingOrDropping) / count,
            endBelowTargetCount: target == nil ? nil : phrases.filter { $0.endBelowTarget == true }.count,
            possibleFryCount: phrases.filter(\.possibleFry).count,
            outOfTargetAtEndFraction: outOfTarget.flatMap { $0 > 0 ? Double(outOfTargetAtEnd) / Double($0) : nil },
            endFrameShare: voiced.isEmpty ? nil : Double(endFrames) / Double(voiced.count)
        )
    }

    /// [s] 피치 점 사이 간격: 이웃한 점의 시각 차이의 중앙값. 점이 둘보다 적으면 48 kHz의 기본 간격.
    /// 샘플레이트에 따라 간격이 달라서(44.1 kHz 23.2 ms, 16 kHz 파일 64 ms) 녹음마다 알아낸다.
    static func frameInterval(of readings: [PitchReading]) -> TimeInterval {
        let gaps = zip(readings.dropFirst(), readings).map { $0.time - $1.time }.filter { $0 > 0 }.sorted()
        return gaps.isEmpty ? PitchHistory.readingInterval : PitchSummary.percentile(gaps, 0.5)
    }

    /// `frames`(시간 순서의 유성 프레임)에서 `ceiling` [Hz]보다 낮은 프레임이 가장 길게 이어진 수.
    /// 사이에 무성음 프레임이 끼면(시각 차이가 한 칸 반보다 크면) 이어진 것으로 보지 않는다.
    private static func longestRun(of frames: [Frame], below ceiling: Double, interval: TimeInterval) -> Int {
        var longest = 0
        var run = 0
        var previousTime: TimeInterval?
        for frame in frames {
            let adjacent = previousTime.map { frame.time - $0 <= interval * 1.5 } ?? false
            run = frame.frequency < ceiling ? (adjacent ? run : 0) + 1 : 0
            longest = max(longest, run)
            previousTime = frame.time
        }
        return longest
    }
}
