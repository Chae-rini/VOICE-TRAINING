import SwiftUI

/// 현재 피치 숫자 + 최근 10초 피치 그래프 + 목표 범위 슬라이더.
/// 녹음 중에는 실시간으로, 녹음을 다시 들을 때는 그때의 곡선을 소리와 같은 속도로 흘려 보여준다.
/// 내 기준 목소리를 쟀으면 그 중앙값을 점선으로 보여 준다. 목표 범위는 기준을 잰 뒤에 생긴다 (방향을 미리 정하지 않음).
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

    private let axisRange = PitchDetector.frequencyRange  // [Hz] 세로축 70~400
    private let gridStep = 50.0                            // [Hz] 눈금 간격
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
                VStack(spacing: 12) {
                    currentPitchLabel(displayedFrequency(at: endTime))
                    Canvas { context, size in
                        drawGraph(in: &context, size: size, endTime: endTime)
                    }
                    .frame(height: 220)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
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
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 그래프

    private func drawGraph(in context: inout GraphicsContext, size: CGSize, endTime: TimeInterval) {
        // 왼쪽은 Hz 숫자, 아래는 시간 표시 자리로 비워 둔다.
        let plot = CGRect(x: 40, y: 12, width: size.width - 52, height: size.height - 36)

        func y(_ frequency: Double) -> CGFloat {
            let ratio = (frequency - axisRange.lowerBound) / (axisRange.upperBound - axisRange.lowerBound)
            return plot.maxY - CGFloat(ratio) * plot.height
        }

        // 목표 범위 띠
        if let target {
            let band = CGRect(x: plot.minX, y: y(target.upperBound), width: plot.width,
                              height: y(target.lowerBound) - y(target.upperBound))
            context.fill(Path(band), with: .color(targetColor.opacity(UllimColor.bandOpacity)))
        }

        // 50Hz 간격 눈금 (100, 150, …, 400) + 아래 경계 70
        let ticks = [axisRange.lowerBound] + Array(stride(from: 100.0, through: axisRange.upperBound, by: gridStep))
        for frequency in ticks {
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

        let dotSize: CGFloat = 4
        var inside = Path()
        var outside = Path()
        var lonelyInside = Path()
        var lonelyOutside = Path()
        for segment in history.voicedSegments(within: visibleTimes) {
            // 앞뒤로 이어진 점이 없는 외톨이 점은 선이 안 보이므로 작은 점으로 그린다.
            if segment.count == 1, let only = segment.first, let p = point(only) {
                let dot = CGRect(x: p.x - dotSize / 2, y: p.y - dotSize / 2, width: dotSize, height: dotSize)
                if isInTarget(only.frequency) {
                    lonelyInside.addEllipse(in: dot)
                } else {
                    lonelyOutside.addEllipse(in: dot)
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
        let line = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        context.stroke(outside, with: .color(outOfRangeColor), style: line)
        context.stroke(inside, with: .color(inRangeColor), style: line)
        context.fill(lonelyOutside, with: .color(outOfRangeColor))
        context.fill(lonelyInside, with: .color(inRangeColor))
    }

    // MARK: - 목표 범위

    private var targetRangeControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("목표 범위")
                Spacer()
                if let target {
                    Text("\(Int(target.lowerBound)) – \(Int(target.upperBound)) Hz")
                        .monospacedDigit()
                        .foregroundStyle(targetColor)
                }
            }
            .font(.subheadline.weight(.medium))

            if target != nil {
                slider("하한", value: lowerBinding)
                slider("상한", value: upperBinding)
            } else {
                Text("아직 목표 범위가 없어요. 내 목소리를 먼저 재면 그 높이를 기준으로 목표 범위를 만들어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // 기준에서 많이 떨어진 목표: 막거나 권하지 않고, 목 상태만 확인하도록 부드럽게 알린다.
            if let target, let baselineMedian, VoiceBaseline.isFar(target, from: baselineMedian) {
                Label("기준 목소리와 꽤 떨어진 범위예요. 목에 무리가 없는지 천천히 확인해 보세요.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("편하게 낼 수 있는 높이로 정하세요. 목이 불편하면 잠시 쉬어 가요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: onMeasure) {
                Label(baselineMedian.map { "내 목소리 다시 재기 · 기준 \(Int($0.rounded())) Hz" } ?? "내 목소리 재기",
                      systemImage: "waveform")
            }
            .font(.footnote)
            .buttonStyle(.bordered)
            .tint(baselineColor)  // 내 기준 색(보라): 기준 점선과 같은 색
            .disabled(!canMeasure)
        }
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .font(.footnote)
                .frame(width: 32, alignment: .leading)
            Slider(value: value, in: axisRange) {
                Text("목표 \(title)")
            }
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
