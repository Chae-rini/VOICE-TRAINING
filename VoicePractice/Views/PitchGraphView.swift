import SwiftUI

/// 현재 피치 숫자 + 최근 10초 피치 그래프 + 목표 범위 슬라이더.
/// 녹음 중에는 실시간으로, 녹음을 다시 들을 때는 그때의 곡선을 소리와 같은 속도로 흘려 보여준다.
/// 내 기준 목소리를 쟀으면 그 중앙값을 점선으로 보여 준다. 목표 범위는 기준을 잰 뒤에 생긴다 (방향을 미리 정하지 않음).
/// 세로축은 반음 눈금이다 (PitchScale): 같은 반음 폭은 어느 높이에서든 같은 길이로 그려진다.
struct PitchGraphView: View {
    let history: PitchHistory
    /// 녹음 중의 현재 피치 [Hz]. 다시 듣는 중에는 기록에서 재생 위치의 값을 찾아 쓴다.
    let currentFrequency: Double?
    let clock: GraphClock
    /// 큰 숫자 아래의 안내 문구 ("현재 목소리 높이", "녹음 다시 듣는 중" 등)
    let caption: String
    /// 연습 중에는 내 목소리 재기를 막는다.
    var canMeasure = true
    /// "내 목소리 재기" 화면을 연다.
    var onMeasure: () -> Void = {}

    @AppStorage(TargetRangeStore.lowerKey) private var targetLower: Double?
    @AppStorage(TargetRangeStore.upperKey) private var targetUpper: Double?
    @AppStorage(TargetRangeStore.baselineMedianKey) private var baselineMedian: Double?
    /// 목표 범위 슬라이더를 펼쳤는지 (평소에는 한 줄로 접어 둔다)
    @State private var isAdjustingTarget = false

    private let axisRange = PitchDetector.frequencyRange  // [Hz] 세로축 70~400 (반음 눈금)
    private let minimumGap = 10.0                          // [Hz] 하한과 상한의 최소 간격
    /// 목표 범위 안의 목소리 (분홍). 목표 범위 밖은 회색.
    private let inRangeColor = UllimColor.voice
    private let outOfRangeColor = UllimColor.inactive
    /// 목표 범위 띠 (파랑 채움)
    private let targetColor = UllimColor.target
    /// 기준선 색. 목표 범위 띠(파랑 채움)와 확실히 다르게 보이도록 보라 점선으로 그린다.
    private let baselineColor = UllimColor.reference

    /// 저장된 목표 범위. 아직 없으면 nil.
    private var target: ClosedRange<Double>? {
        guard let targetLower, let targetUpper else { return nil }
        return min(targetLower, targetUpper)...max(targetLower, targetUpper)
    }

    var body: some View {
        VStack(spacing: 12) {
            // 녹음 중이거나 다시 듣는 중에만 초당 30번 다시 그린다. 멈추면 그 순간의 10초를 그대로 보여준다.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !clock.isMoving)) { _ in
                let endTime = clock.endTime(now: AudioClock.now)
                let frequency = displayedFrequency(at: endTime)
                VStack(spacing: 12) {
                    currentPitchLabel(frequency)
                    Canvas { context, size in
                        drawGraph(in: &context, size: size, endTime: endTime)
                    }
                    .frame(height: 220)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    // 눈금 숫자는 그래프 왼쪽의 정해진 칸(40pt)에 들어가야 해서 아주 큰 글자에서는 더 키우지 않는다.
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    // 그림이라 VoiceOver가 읽을 것이 없으므로, 그래프가 보여 주는 내용을 말로 붙인다.
                    .accessibilityElement()
                    .accessibilityLabel("최근 10초 목소리 높이 그래프")
                    .accessibilityValue(graphDescription(frequency))
                }
            }
            targetRangeControls
        }
    }

    private func displayedFrequency(at endTime: TimeInterval) -> Double? {
        if case .replay = clock {
            return history.frequency(at: endTime)
        }
        return currentFrequency
    }

    // MARK: - 현재 피치

    private func currentPitchLabel(_ frequency: Double?) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(frequency.map { "\(Int($0.rounded()))" } ?? "–")
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isInTarget(frequency) ? inRangeColor : .primary)
                Text("Hz")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            // 색을 구분하기 어려워도 알 수 있게 목표 범위 안이면 글자로도 적는다 (판정이 아니라 사실만).
            Text(isInTarget(frequency) ? "\(caption) · 목표 범위 안" : caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// VoiceOver로 읽을 그래프 설명. 예: "목표 범위 130에서 320 Hz, 기준 200 Hz, 지금 152 Hz, 목표 범위 안"
    private func graphDescription(_ frequency: Double?) -> String {
        var parts: [String] = []
        if let target {
            parts.append("목표 범위 \(Int(target.lowerBound))에서 \(Int(target.upperBound)) Hz")
        } else {
            parts.append("목표 범위 없음")
        }
        if let baselineMedian {
            parts.append("기준 \(Int(baselineMedian.rounded())) Hz")
        }
        if let frequency {
            parts.append("지금 \(Int(frequency.rounded())) Hz")
            if target != nil {
                parts.append(isInTarget(frequency) ? "목표 범위 안" : "목표 범위 밖")
            }
        } else {
            parts.append("지금 잡힌 목소리 없음")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - 그래프

    private func drawGraph(in context: inout GraphicsContext, size: CGSize, endTime: TimeInterval) {
        // 왼쪽은 Hz 숫자, 아래는 시간 표시 자리로 비워 둔다.
        let plot = CGRect(x: 40, y: 12, width: size.width - 52, height: size.height - 36)

        // 반음 눈금: Hz가 아니라 비율(반음) 간격으로 위치를 정한다.
        func y(_ frequency: Double) -> CGFloat {
            plot.maxY - CGFloat(PitchScale.position(of: frequency, in: axisRange)) * plot.height
        }

        // 목표 범위 띠
        if let target {
            let band = CGRect(x: plot.minX, y: y(target.upperBound), width: plot.width,
                              height: y(target.lowerBound) - y(target.upperBound))
            context.fill(Path(band), with: .color(targetColor.opacity(UllimColor.bandOpacity)))
        }

        // 눈금 70·100·150·200·300·400 Hz (반음 눈금에서 고르게 보이는 숫자)
        for frequency in PitchScale.ticks(in: axisRange) {
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: y(frequency)))
            line.addLine(to: CGPoint(x: plot.maxX, y: y(frequency)))
            context.stroke(line, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
            context.draw(
                Text("\(Int(frequency))").font(.caption2).foregroundStyle(.secondary),
                at: CGPoint(x: plot.minX - 6, y: y(frequency)),
                anchor: .trailing
            )
        }
        context.draw(
            Text("10초 전").font(.caption2).foregroundStyle(.secondary),
            at: CGPoint(x: plot.minX, y: plot.maxY + 6),
            anchor: .topLeading
        )
        context.draw(
            Text("지금").font(.caption2).foregroundStyle(.secondary),
            at: CGPoint(x: plot.maxX, y: plot.maxY + 6),
            anchor: .topTrailing
        )

        // 내 기준 목소리(중앙값): 얇은 점선과 "기준" 글자
        if let baselineMedian {
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: y(baselineMedian)))
            line.addLine(to: CGPoint(x: plot.maxX, y: y(baselineMedian)))
            context.stroke(line, with: .color(baselineColor.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            context.draw(
                Text("기준").font(.caption2.weight(.medium)).foregroundStyle(baselineColor),
                at: CGPoint(x: plot.minX + 4, y: y(baselineMedian) - 2),
                anchor: .bottomLeading
            )
        }

        // 피치 꺾은선: 오른쪽이 지금, 왼쪽으로 갈수록 과거. 무음 구간은 선을 끊어 빈칸으로 남긴다.
        // 선분마다 두 끝점의 가운데 높이가 목표 범위 안이면 분홍(목소리 색), 밖이면 회색으로 칠한다.
        func point(_ reading: PitchReading) -> CGPoint? {
            guard let frequency = reading.frequency else { return nil }
            let age = endTime - reading.time  // [s] 몇 초 전인지
            let x = min(plot.maxX, plot.maxX - CGFloat(age / history.visibleDuration) * plot.width)
            return CGPoint(x: x, y: y(frequency))
        }
        // 보이는 10초(왼쪽 끝을 조금 넘는 데까지)만 그린다. 다시 듣는 중에는 아직 재생되지 않은 뒷부분을 그리지 않는다.
        let visibleTimes = (endTime - history.visibleDuration - 0.5)...endTime

        // 목표 범위 안은 굵게, 밖은 가늘게: 색을 구분하기 어려워도 굵기로 알 수 있다.
        let insideWidth: CGFloat = 3.5
        let outsideWidth: CGFloat = 2
        let dotSize: CGFloat = 5
        let outsideDotSize: CGFloat = 3.5
        var inside = Path()
        var outside = Path()
        var lonelyInside = Path()
        var lonelyOutside = Path()
        for segment in history.voicedSegments(within: visibleTimes) {
            // 앞뒤로 이어진 점이 없는 외톨이 점은 선이 안 보이므로 작은 점으로 그린다.
            if segment.count == 1, let only = segment.first, let p = point(only) {
                if isInTarget(only.frequency) {
                    lonelyInside.addEllipse(in: CGRect(x: p.x - dotSize / 2, y: p.y - dotSize / 2,
                                                       width: dotSize, height: dotSize))
                } else {
                    lonelyOutside.addEllipse(in: CGRect(x: p.x - outsideDotSize / 2, y: p.y - outsideDotSize / 2,
                                                        width: outsideDotSize, height: outsideDotSize))
                }
                continue
            }
            for (previous, next) in zip(segment, segment.dropFirst()) {
                guard let a = point(previous), let b = point(next),
                      let f1 = previous.frequency, let f2 = next.frequency else { continue }
                if isInTarget((f1 + f2) / 2) {
                    inside.move(to: a)
                    inside.addLine(to: b)
                } else {
                    outside.move(to: a)
                    outside.addLine(to: b)
                }
            }
        }

        // 10초보다 오래된 부분은 그래프 왼쪽 밖으로 잘라 낸다.
        context.clip(to: Path(plot.insetBy(dx: -dotSize, dy: -dotSize)))
        context.stroke(outside, with: .color(outOfRangeColor),
                       style: StrokeStyle(lineWidth: outsideWidth, lineCap: .round, lineJoin: .round))
        context.stroke(inside, with: .color(inRangeColor),
                       style: StrokeStyle(lineWidth: insideWidth, lineCap: .round, lineJoin: .round))
        context.fill(lonelyOutside, with: .color(outOfRangeColor))
        context.fill(lonelyInside, with: .color(inRangeColor))
    }

    // MARK: - 목표 범위

    private var targetRangeControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 한 줄에 들어가면 한 줄로, 아주 큰 글자에서는 제목·값·버튼을 한 줄씩 쌓는다.
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("목표 범위")
                    Spacer()
                    targetValue
                    adjustButton
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("목표 범위")
                    targetValue
                    adjustButton
                }
            }
            .font(.subheadline.weight(.medium))

            // 기준에서 많이 떨어진 목표: 막거나 권하지 않고, 목 상태만 확인하도록 부드럽게 알린다 (접혀 있어도 보인다).
            if let target, let baselineMedian, VoiceBaseline.isFar(target, from: baselineMedian) {
                Label("기준 목소리와 꽤 떨어진 범위예요. 목에 무리가 없는지 천천히 확인해 보세요.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 목표 범위는 자주 바꾸지 않으므로 평소에는 접어 둔다. 아직 없으면 만드는 방법을 바로 보여 준다.
            if target == nil {
                Text("아직 목표 범위가 없어요. 내 목소리를 먼저 재면 그 높이를 기준으로 목표 범위를 만들어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                measureButton
            } else if isAdjustingTarget, let target {
                slider("하한", value: lowerBinding)
                slider("상한", value: upperBinding)
                // 폭을 반음으로도 알려 준다: 같은 Hz 폭이라도 낮은 쪽이 귀로는 더 넓다.
                Text("목표 범위의 폭은 반음 \(String(format: "%.1f", PitchScale.semitones(from: target.lowerBound, to: target.upperBound)))개예요.")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("편하게 낼 수 있는 높이로 정하세요. 목이 불편하면 잠시 쉬어 가요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                measureButton
            }
        }
    }

    /// "130 – 320 Hz" (값 중간에서 줄이 바뀌지 않게). 목표 범위가 없으면 비어 있다.
    @ViewBuilder
    private var targetValue: some View {
        if let target {
            Text("\(Int(target.lowerBound)) – \(Int(target.upperBound)) Hz")
                .monospacedDigit()
                .foregroundStyle(targetColor)
                .fixedSize()
        }
    }

    /// 목표 범위 슬라이더를 펼치고 접는 버튼. 목표 범위가 없으면 비어 있다.
    @ViewBuilder
    private var adjustButton: some View {
        if target != nil {
            Button {
                withAnimation(.snappy) { isAdjustingTarget.toggle() }
            } label: {
                Label("조정", systemImage: isAdjustingTarget ? "chevron.up" : "chevron.down")
            }
            .font(.footnote)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityHint(isAdjustingTarget ? "목표 범위 슬라이더를 접어요" : "목표 범위 슬라이더를 펼쳐요")
        }
    }

    private var measureButton: some View {
        Button(action: onMeasure) {
            Label(baselineMedian.map { "내 목소리 다시 재기 · 기준 \(Int($0.rounded())) Hz" } ?? "내 목소리 재기",
                  systemImage: "waveform")
        }
        .font(.footnote)
        .buttonStyle(.bordered)
        .tint(baselineColor)  // 내 기준 색(보라): 기준 점선과 같은 색
        .disabled(!canMeasure)
    }

    /// 목표 범위 슬라이더. 그래프와 같은 반음 눈금이라, 같은 거리만큼 끌면 어느 높이에서든 같은 반음만큼 움직인다.
    /// 슬라이더는 0~1 위치를 다루고, 저장·표시는 Hz로 한다.
    private func slider(_ title: String, value: Binding<Double>) -> some View {
        let position = Binding(
            get: { PitchScale.position(of: value.wrappedValue, in: axisRange) },
            set: { value.wrappedValue = PitchScale.frequency(atPosition: $0, in: axisRange) }
        )
        return HStack {
            Text(title)
                .font(.footnote)
                .frame(width: 32, alignment: .leading)
            Slider(value: position, in: 0...1) {
                Text("목표 \(title)")
            }
            // VoiceOver가 0~1 위치(퍼센트) 대신 Hz를 읽게 한다.
            .accessibilityValue("\(Int(value.wrappedValue)) Hz")
        }
    }

    // 값은 5Hz 단위로 맞추고, 하한이 상한을 넘지 않도록 서로 최소 간격을 유지한다.
    // 슬라이더는 목표 범위가 있을 때만 보이므로 값이 비어 있지 않다.
    private var lowerBinding: Binding<Double> {
        Binding(
            get: { target?.lowerBound ?? axisRange.lowerBound },
            set: { targetLower = min(snapped($0), (target?.upperBound ?? axisRange.upperBound) - minimumGap) }
        )
    }

    private var upperBinding: Binding<Double> {
        Binding(
            get: { target?.upperBound ?? axisRange.upperBound },
            set: { targetUpper = max(snapped($0), (target?.lowerBound ?? axisRange.lowerBound) + minimumGap) }
        )
    }

    private func snapped(_ frequency: Double) -> Double {
        (frequency / 5).rounded() * 5
    }

    private func isInTarget(_ frequency: Double?) -> Bool {
        guard let frequency, let target else { return false }
        return target.contains(frequency)
    }
}

#Preview {
    PitchGraphView(history: PitchHistory(), currentFrequency: 196, clock: .frozen(nil), caption: "현재 목소리 높이")
        .padding()
}
