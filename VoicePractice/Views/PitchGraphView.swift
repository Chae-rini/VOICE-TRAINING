import SwiftUI

/// 현재 피치 숫자 + 피치 그래프. [높이] 화면 위에 고정되어, 아래의 문장·대본을 넘겨도 늘 보인다.
/// 가로축은 ‘들려줄 길이’(10초~3분)다 (GraphWindow). 녹음 중에는 오른쪽 끝이 지금이고 곡선과 시간 눈금이 왼쪽으로 흐르며,
/// 다시 들을 때는 녹음 전체를 그대로 두고 재생 위치에 세로선을 움직인다.
/// 내 기준 목소리를 쟀으면 그 중앙값을 점선으로 보여 준다. 목표 범위는 기준을 잰 뒤에 생긴다 (방향을 미리 정하지 않음).
/// 세로축은 반음 눈금이다 (PitchScale): 같은 반음 폭은 어느 높이에서든 같은 길이로 그려진다.
struct PitchGraphView: View {
    let history: PitchHistory
    /// 녹음 중의 현재 피치 [Hz]. 다시 듣는 중에는 기록에서 재생 위치의 값을 찾아 쓴다.
    let currentFrequency: Double?
    let clock: GraphClock
    /// 큰 숫자 아래의 안내 문구 ("현재 목소리 높이", "녹음 다시 듣는 중" 등)
    let caption: String
    /// [s] 아직 녹음이 없을 때 보여 줄 가로축 길이 (지금 ‘들려줄 길이’)
    var idleDuration: TimeInterval = PracticeDuration.defaultSeconds
    /// 읽기 모드: 대본을 읽는 동안 그래프를 낮게(150pt), 큰 숫자를 한 줄로 작게 줄여 대본 자리를 넓힌다.
    var isCompact = false

    @Environment(\.displayScale) private var displayScale

    @AppStorage(TargetRangeStore.lowerKey) private var targetLower: Double?
    @AppStorage(TargetRangeStore.upperKey) private var targetUpper: Double?
    @AppStorage(TargetRangeStore.baselineMedianKey) private var baselineMedian: Double?
    /// 내 기준 목소리의 F2 중앙값 (공명 밝기 막대의 가운데)
    @AppStorage(TargetRangeStore.baselineF2Key) private var baselineF2: Double?

    private let axisRange = PitchDetector.frequencyRange  // [Hz] 세로축 70~400 (반음 눈금)
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
        // 녹음 중이거나 다시 듣는 중에만 초당 30번 다시 그린다. 멈추면 마지막 녹음을 그대로 보여 준다.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !clock.isMoving)) { _ in
            let now = AudioClock.now
            let endTime = clock.endTime(now: now)
            // 아직 녹음이 없으면 지금 ‘들려줄 길이’만큼의 빈 가로축을 보여 준다.
            let window = clock.window(now: now) ?? GraphWindow(start: endTime - idleDuration, duration: idleDuration)
            let frequency = displayedFrequency(at: endTime)
            VStack(spacing: isCompact ? 4 : 8) {
                if isCompact {
                    compactPitchLabel(frequency)
                } else {
                    currentPitchLabel(frequency)
                }
                Canvas { context, size in
                    drawGraph(in: &context, size: size, window: window, endTime: endTime)
                }
                .frame(height: isCompact ? 150 : 220)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                // 눈금 숫자는 그래프 왼쪽의 정해진 칸(40pt)에 들어가야 해서 아주 큰 글자에서는 더 키우지 않는다.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                // 그림이라 VoiceOver가 읽을 것이 없으므로, 그래프가 보여 주는 내용을 말로 붙인다.
                .accessibilityElement()
                .accessibilityLabel("목소리 높이 그래프, 가로축 \(PitchSummary.durationLabel(window.duration))")
                .accessibilityValue(graphDescription(frequency, window: window, endTime: endTime))

                meterRows(endTime: endTime)
            }
        }
    }

    // MARK: - 음량·공명 막대

    /// 그래프 아래 두 줄: 지금 소리 크기(dBFS)와 공명 밝기(F2). 녹음 중·다시 듣는 중에만 값이 있다.
    private func meterRows(endTime: TimeInterval) -> some View {
        let isLive: Bool
        if case .live = clock {
            isLive = true
        } else {
            isLive = false
        }
        // 최근 3초 남짓만 꺼내 계산한다 (화면이 초당 30번 부른다).
        let recent = clock.isMoving
            ? Array(history.readings(in: (endTime - LevelMeter.loudSeconds - 0.2)...endTime))
            : []
        let level = LevelMeter.smoothedLevel(recent, at: endTime)
        // 아주 큰 소리 안내는 지금 녹음하는 동안만 (다시 듣는 소리에는 하지 않는다)
        let isLoud = isLive && LevelMeter.isSustainedLoud(recent, at: endTime)
        let resonance = ResonanceMeter.current(recent, at: endTime)

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                meterTitle("음량")
                levelBar(level, isLoud: isLoud)
                meterValue(level.map { "\(Int($0.rounded())) dBFS" } ?? "– dBFS")
            }
            HStack(spacing: 8) {
                meterTitle("공명")
                if let baselineF2 {
                    resonanceBar(resonance, baseline: baselineF2)
                } else {
                    Text("내 목소리 재기를 하면 기준이 생겨요")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                meterValue(resonance.map { "F2 \(Int($0.f2.rounded()))" } ?? "F2 –")
            }
            if isLoud {
                Label("소리가 꽤 커요. 목에 무리가 없는지 확인해 보세요.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        // 화면 위에 고정된 영역이라 아주 큰 글자에서는 더 키우지 않는다.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("음량과 공명 밝기")
        .accessibilityValue(meterDescription(level: level, isLoud: isLoud, resonance: resonance))
    }

    private func meterTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 30, alignment: .leading)
    }

    private func meterValue(_ value: String) -> some View {
        Text(value)
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(width: 64, alignment: .trailing)
    }

    /// 소리 크기 막대 (−60 ~ 0 dBFS). 크다·작다를 평가하는 색은 쓰지 않고, 아주 큰 소리가 이어질 때만 주황.
    private func levelBar(_ level: Double?, isLoud: Bool) -> some View {
        Capsule()
            .fill(Color(.tertiarySystemFill))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(isLoud ? Color.orange : Color.secondary.opacity(0.7))
                        .frame(width: proxy.size.width * LevelMeter.position(level ?? LevelMeter.range.lowerBound))
                }
            }
            .frame(height: 6)
    }

    /// 공명 밝기 막대: 가운데(보라 눈금)가 내 기준 F2, 왼쪽 어두운 쪽 · 오른쪽 밝은 쪽. 지금 값은 분홍 점.
    /// 목소리가 높아 값이 불확실하면 속이 빈 점으로 그린다 (모음 지도와 같은 규칙).
    private func resonanceBar(_ reading: ResonanceMeter.Reading?, baseline: Double) -> some View {
        HStack(spacing: 4) {
            Text("어두운")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Capsule()
                .fill(Color(.tertiarySystemFill))
                .frame(height: 6)
                .overlay {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(UllimColor.reference)
                            .frame(width: 2, height: 12)
                            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        if let reading {
                            let x = proxy.size.width * ResonanceMeter.position(f2: reading.f2, baseline: baseline)
                            Group {
                                if reading.isUncertain {
                                    Circle().strokeBorder(UllimColor.voice, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                                } else {
                                    Circle().fill(UllimColor.voice)
                                }
                            }
                            .frame(width: 10, height: 10)
                            .position(x: x, y: proxy.size.height / 2)
                        }
                    }
                }
            Text("밝은")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// VoiceOver: "음량 −24 dBFS, 공명 밝기 F2 1650 Hz, 기준보다 밝은 쪽"
    private func meterDescription(level: Double?, isLoud: Bool, resonance: ResonanceMeter.Reading?) -> String {
        var parts = [level.map { "음량 \(Int($0.rounded())) dBFS" } ?? "음량 없음"]
        if isLoud {
            parts.append("소리가 꽤 커요")
        }
        if let resonance {
            var text = "공명 밝기 F2 \(Int(resonance.f2.rounded())) Hz"
            if let baselineF2 {
                let position = ResonanceMeter.position(f2: resonance.f2, baseline: baselineF2)
                text += position > 0.55 ? ", 기준보다 밝은 쪽" : (position < 0.45 ? ", 기준보다 어두운 쪽" : ", 기준과 비슷")
            }
            if resonance.isUncertain {
                text += ", 불확실"
            }
            parts.append(text)
        } else {
            parts.append("공명 밝기 없음")
        }
        return parts.joined(separator: ", ")
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

    /// 읽기 모드의 한 줄: "152 Hz · 현재 목소리 높이 · 목표 범위 안"
    private func compactPitchLabel(_ frequency: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(frequency.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isInTarget(frequency) ? inRangeColor : .primary)
            Text("Hz")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(isInTarget(frequency) ? "\(caption) · 목표 범위 안" : caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        // 고정된 영역이라 아주 큰 글자에서도 한 줄을 지킨다.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .combine)
    }

    /// VoiceOver로 읽을 그래프 설명.
    /// 예: "가로축 1분, 녹음 시작부터 0:35, 목표 범위 130에서 320 Hz, 기준 200 Hz, 지금 152 Hz, 목표 범위 안"
    private func graphDescription(_ frequency: Double?, window: GraphWindow, endTime: TimeInterval) -> String {
        var parts = ["가로축 \(PitchSummary.durationLabel(window.duration))"]
        let elapsed = GraphWindow.timeLabel(endTime - (window.recordingStart ?? window.start))
        if case .replay = clock {
            parts.append("재생 위치 \(elapsed)")
        } else if window.recordingStart != nil {
            parts.append("녹음 시작부터 \(elapsed)")
        }
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

    private func drawGraph(in context: inout GraphicsContext, size: CGSize, window: GraphWindow, endTime: TimeInterval) {
        // 왼쪽은 Hz 숫자, 아래는 시간 표시 자리로 비워 둔다.
        let plot = CGRect(x: 40, y: 12, width: size.width - 52, height: size.height - 36)

        // 가로: 가로축 구간 안의 위치. 세로: 반음 눈금 (Hz가 아니라 비율(반음) 간격으로 위치를 정한다).
        func x(_ time: TimeInterval) -> CGFloat {
            plot.minX + CGFloat(window.position(of: time)) * plot.width
        }
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

        // 시간 눈금: 녹음을 시작한 때부터 몇 분 몇 초인지 ("0:30"). 양 끝 글자는 그래프 밖으로 나가지 않게 붙인다.
        for tick in window.ticks {
            let tickX = x(tick.time)
            var line = Path()
            line.move(to: CGPoint(x: tickX, y: plot.minY))
            line.addLine(to: CGPoint(x: tickX, y: plot.maxY))
            context.stroke(line, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            let anchor: UnitPoint = tickX < plot.minX + 12 ? .topLeading : (tickX > plot.maxX - 12 ? .topTrailing : .top)
            context.draw(
                Text(tick.label).font(.caption2).monospacedDigit().foregroundStyle(.secondary),
                at: CGPoint(x: tickX, y: plot.maxY + 6),
                anchor: anchor
            )
        }

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

        // 녹음 시작선: 녹음을 시작한 때가 가로축 안에 있을 때만 (오래 녹음해 흘러가면 왼쪽 밖으로 사라진다).
        // 첫 녹음은 실선 "시작", 반복 루프에서 다시 녹음한 것은 점선 "2번째"처럼 모양을 다르게 한다.
        if window.showsStartLine, let recordingStart = window.recordingStart {
            let startX = max(x(recordingStart), plot.minX)
            var line = Path()
            line.move(to: CGPoint(x: startX, y: plot.minY))
            line.addLine(to: CGPoint(x: startX, y: plot.maxY))
            let style = window.isRoundBoundary
                ? StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                : StrokeStyle(lineWidth: 1.5)
            context.stroke(line, with: .color(.secondary.opacity(0.8)), style: style)
            // 막 시작해 선이 오른쪽 끝 가까이 있으면 글자를 선 왼쪽에 붙인다 (그래프 밖으로 나가지 않게).
            let labelOnLeft = startX > plot.maxX - 44
            context.draw(
                Text(window.startLabel).font(.caption2.weight(.medium)).foregroundStyle(.secondary),
                at: CGPoint(x: labelOnLeft ? startX - 4 : startX + 4, y: plot.minY + 2),
                anchor: labelOnLeft ? .topTrailing : .topLeading
            )
        }

        // 피치 꺾은선: 무음 구간은 선을 끊어 빈칸으로 남긴다.
        // 선분마다 두 끝점의 가운데 높이가 목표 범위 안이면 분홍(목소리 색), 밖이면 회색으로 칠한다.
        func point(_ reading: PitchReading) -> CGPoint? {
            guard let frequency = reading.frequency else { return nil }
            return CGPoint(x: x(reading.time), y: y(frequency))
        }
        // 녹음 중·멈춘 화면은 "지금"까지, 다시 듣는 중에는 녹음 전체를 그린다 (아직 재생되지 않은 뒷부분은 흐리게).
        let isReplaying: Bool
        if case .replay = clock {
            isReplaying = true
        } else {
            isReplaying = false
        }
        // 화면 폭보다 촘촘한 점은 같은 픽셀 열마다 하나로 묶는다 (3분이면 점이 8천 개가 넘는다).
        let segments = history.displaySegments(in: window, until: isReplaying ? window.end : endTime,
                                               width: Double(plot.width * displayScale))

        // 목표 범위 안은 굵게, 밖은 가늘게: 색을 구분하기 어려워도 굵기로 알 수 있다.
        let insideWidth: CGFloat = 3.5
        let outsideWidth: CGFloat = 2
        let dotSize: CGFloat = 5
        let outsideDotSize: CGFloat = 3.5
        var inside = Path()
        var outside = Path()
        var lonelyInside = Path()
        var lonelyOutside = Path()
        for segment in segments {
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
        func drawCurve(in layer: inout GraphicsContext) {
            layer.stroke(outside, with: .color(outOfRangeColor),
                         style: StrokeStyle(lineWidth: outsideWidth, lineCap: .round, lineJoin: .round))
            layer.stroke(inside, with: .color(inRangeColor),
                         style: StrokeStyle(lineWidth: insideWidth, lineCap: .round, lineJoin: .round))
            layer.fill(lonelyOutside, with: .color(outOfRangeColor))
            layer.fill(lonelyInside, with: .color(inRangeColor))
        }

        // 가로축 구간 밖(흘러간 앞부분)은 그래프 밖으로 잘라 낸다.
        context.clip(to: Path(plot.insetBy(dx: -dotSize, dy: -dotSize)))
        guard isReplaying else {
            drawCurve(in: &context)
            return
        }
        // 다시 듣는 중: 재생한 앞부분은 그대로, 아직 재생하지 않은 뒷부분은 흐리게, 재생 위치에 세로선
        let playheadX = min(max(x(endTime), plot.minX), plot.maxX)
        context.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: 0, y: 0, width: playheadX, height: size.height)))
            drawCurve(in: &layer)
        }
        context.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: playheadX, y: 0, width: size.width - playheadX, height: size.height)))
            layer.opacity = 0.3
            drawCurve(in: &layer)
        }
        var playhead = Path()
        playhead.move(to: CGPoint(x: playheadX, y: plot.minY))
        playhead.addLine(to: CGPoint(x: playheadX, y: plot.maxY))
        context.stroke(playhead, with: .color(.primary.opacity(0.6)), lineWidth: 1.5)
    }

    private func isInTarget(_ frequency: Double?) -> Bool {
        guard let frequency, let target else { return false }
        return target.contains(frequency)
    }
}

/// 음량·공명 막대 보는 법. [높이] 화면에서 그래프 아래, 문장과 함께 스크롤된다. 막대의 한계를 숨기지 않는다.
struct MeterGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("음량은 이 기기 마이크가 받은 소리 크기(dBFS, 0이 마이크가 받을 수 있는 최대)예요. 마이크마다 값이 달라서 귀로 듣는 절대 데시벨(dB SPL)이 아니에요.")
            Text("공명 밝기는 최근 2.5초 목소리의 둘째 포먼트(F2) 중앙값이에요. 가운데 보라 선은 내 목소리 재기 때의 값이에요. 문장 속 공명은 어떤 모음을 말했는지에 따라 달라져요. 같은 대본을 읽을 때 비교하면 정확해요. 점이 비어 있으면 목소리가 높아 값이 불확실할 수 있어요.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 목표 범위 한 줄(접기·펼치기)과 슬라이더, 내 목소리 재기 버튼. [높이] 화면에서 그래프 아래, 문장과 함께 스크롤된다.
struct TargetRangeControls: View {
    /// 연습 중에는 내 목소리 재기를 막는다.
    var canMeasure = true
    /// "내 목소리 재기" 화면을 연다.
    var onMeasure: () -> Void = {}

    @AppStorage(TargetRangeStore.lowerKey) private var targetLower: Double?
    @AppStorage(TargetRangeStore.upperKey) private var targetUpper: Double?
    @AppStorage(TargetRangeStore.baselineMedianKey) private var baselineMedian: Double?
    /// 목표 범위 슬라이더를 펼쳤는지 (평소에는 한 줄로 접어 둔다)
    @State private var isAdjustingTarget = false

    private let axisRange = PitchDetector.frequencyRange  // [Hz] 슬라이더 범위 70~400 (그래프와 같은 반음 눈금)
    private let minimumGap = 10.0                          // [Hz] 하한과 상한의 최소 간격
    private let targetColor = UllimColor.target
    private let baselineColor = UllimColor.reference

    /// 저장된 목표 범위. 아직 없으면 nil.
    private var target: ClosedRange<Double>? {
        guard let targetLower, let targetUpper else { return nil }
        return min(targetLower, targetUpper)...max(targetLower, targetUpper)
    }

    var body: some View {
        targetRangeControls
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
}

#Preview {
    VStack {
        PitchGraphView(history: PitchHistory(), currentFrequency: 196, clock: .frozen(nil, at: nil), caption: "현재 목소리 높이")
        TargetRangeControls()
    }
    .padding()
}
