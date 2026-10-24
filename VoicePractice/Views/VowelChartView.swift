import SwiftUI

/// 모음 지도: 가로 F2(왼쪽이 혀 앞쪽), 세로 F1(위가 입을 좁게).
/// 지금 내는 소리를 큰 점으로, 최근 1.5초를 흐린 꼬리로 보여 준다. 녹음을 다시 들을 때는 재생 위치를 따라간다.
/// 내가 잰 모음(내 모음 지도)은 남보라 원과 글자로 표시한다. 성별 평균 같은 기준 위치는 그리지 않는다 (원칙 3).
struct VowelChartView: View {
    let history: PitchHistory
    let clock: GraphClock
    /// 숫자 아래의 안내 문구 ("지금 내는 모음", "녹음을 다시 듣는 중" 등)
    let caption: String
    /// 내가 잰 모음들
    var map = VowelMap()
    /// 비교할 모음. 이 모음을 쟀으면 지금 점과의 차이를 숫자로 보여 준다.
    var selected: KoreanVowel?

    /// [s] 지금 점을 정할 때 모으는 길이 (흔들림 줄이기)
    private let currentWindow: TimeInterval = 0.3
    /// [s] 꼬리 길이
    private let trailWindow: TimeInterval = 1.5
    private let pointColor = Color.teal
    private let trailColor = Color.gray
    /// 내 기준(내 모음 지도) 색. [높이] 탭의 기준 목소리 점선과 같은 색이다.
    private let markerColor = Color.indigo

    var body: some View {
        // 녹음 중이거나 다시 듣는 중에만 초당 30번 다시 그린다.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !clock.isMoving)) { _ in
            let end = clock.endTime(now: AudioClock.now)
            let current = VowelSpace.current(history.readings(in: (end - currentWindow)...end))
            let trail = history.readings(in: (end - trailWindow)...end)
            VStack(spacing: 12) {
                currentLabel(current)
                Canvas { context, size in
                    draw(in: &context, size: size, current: current, trail: trail, end: end)
                }
                .frame(height: 320)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - 숫자

    private func currentLabel(_ point: VowelSpace.Point?) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                value("F1", point?.f1, dimmed: point?.isF1Uncertain == true)
                value("F2", point?.f2, dimmed: false)
            }
            Text(point?.isF1Uncertain == true ? "목소리가 높아 F1(세로)은 정확하지 않을 수 있어요" : caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
            // 내가 잰 같은 모음과의 차이 (어느 쪽이 낫다는 뜻이 아니라 얼마나 다른지만)
            if let point, let selected, let saved = map[selected] {
                Text("내 ‘\(selected.rawValue)’와 비교 · F1 \(signed(point.f1 - saved.f1)) · F2 \(signed(point.f2 - saved.f2)) Hz")
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(markerColor)
            }
        }
    }

    private func signed(_ difference: Double) -> String {
        let value = Int(difference.rounded())
        return value > 0 ? "+\(value)" : "\(value)"
    }

    private func value(_ name: String, _ frequency: Double?, dimmed: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(frequency.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(dimmed ? .secondary : .primary)
            Text("Hz")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 지도

    private func draw(in context: inout GraphicsContext, size: CGSize, current: VowelSpace.Point?,
                      trail: ArraySlice<PitchReading>, end: TimeInterval) {
        // 왼쪽은 F1 숫자, 아래는 F2 숫자와 방향 안내 자리로 비워 둔다.
        let plot = CGRect(x: 44, y: 24, width: size.width - 56, height: size.height - 64)
        func point(f1: Double, f2: Double) -> CGPoint {
            let unit = VowelSpace.position(f1: f1, f2: f2)
            return CGPoint(x: plot.minX + unit.x * plot.width, y: plot.minY + unit.y * plot.height)
        }
        let gridColor = GraphicsContext.Shading.color(.secondary.opacity(0.25))

        // 눈금: 세로축 F1, 가로축 F2
        for f1 in VowelSpace.f1Ticks {
            let y = point(f1: f1, f2: VowelSpace.f2Range.lowerBound).y
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: y))
            line.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(line, with: gridColor, lineWidth: 0.5)
            context.draw(label("\(Int(f1))"), at: CGPoint(x: plot.minX - 6, y: y), anchor: .trailing)
        }
        for f2 in VowelSpace.f2Ticks {
            let x = point(f1: VowelSpace.f1Range.lowerBound, f2: f2).x
            var line = Path()
            line.move(to: CGPoint(x: x, y: plot.minY))
            line.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(line, with: gridColor, lineWidth: 0.5)
            context.draw(label("\(Int(f2))"), at: CGPoint(x: x, y: plot.maxY + 4), anchor: .top)
        }

        // 축 이름과 방향 안내 (입과 혀의 움직임일 뿐, 좋고 나쁨이 아니다)
        context.draw(label("F1", bold: true), at: CGPoint(x: plot.minX - 6, y: plot.minY - 12), anchor: .trailing)
        context.draw(label("입 좁게"), at: CGPoint(x: plot.minX + 4, y: plot.minY - 4), anchor: .bottomLeading)
        context.draw(label("입 크게"), at: CGPoint(x: plot.minX + 4, y: plot.maxY - 4), anchor: .bottomLeading)
        context.draw(label("← 혀 앞쪽"), at: CGPoint(x: plot.minX, y: plot.maxY + 22), anchor: .topLeading)
        context.draw(label("F2", bold: true), at: CGPoint(x: plot.midX, y: plot.maxY + 22), anchor: .top)
        context.draw(label("혀 뒤쪽 →"), at: CGPoint(x: plot.maxX, y: plot.maxY + 22), anchor: .topTrailing)

        // 내 모음 지도: 잰 모음마다 남보라 원과 글자. 길게 내는 동안 흔들린 범위(25%~75%)는 옅은 십자로.
        // 잴 때 F1이 불확실했으면 원을 점선으로 그린다.
        for vowel in KoreanVowel.allCases {
            guard let entry = map[vowel] else { continue }
            let p = point(f1: entry.f1, f2: entry.f2)
            var cross = Path()
            cross.move(to: CGPoint(x: point(f1: entry.f1, f2: entry.f2Spread.upperBound).x, y: p.y))
            cross.addLine(to: CGPoint(x: point(f1: entry.f1, f2: entry.f2Spread.lowerBound).x, y: p.y))
            cross.move(to: CGPoint(x: p.x, y: point(f1: entry.f1Spread.lowerBound, f2: entry.f2).y))
            cross.addLine(to: CGPoint(x: p.x, y: point(f1: entry.f1Spread.upperBound, f2: entry.f2).y))
            context.stroke(cross, with: .color(markerColor.opacity(0.35)), lineWidth: 1.5)

            let isSelected = vowel == selected
            let radius: CGFloat = isSelected ? 15 : 12
            let circle = Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: 2 * radius, height: 2 * radius))
            context.fill(circle, with: .color(markerColor.opacity(isSelected ? 0.22 : 0.10)))
            context.stroke(circle, with: .color(markerColor),
                           style: StrokeStyle(lineWidth: isSelected ? 2 : 1.2, dash: entry.isF1Uncertain ? [3, 3] : []))
            context.draw(Text(vowel.rawValue).font(.caption.weight(.semibold)).foregroundStyle(markerColor), at: p)
        }

        // 꼬리: 최근 1.5초. 오래된 점일수록 흐리게
        for reading in trail {
            guard let formants = reading.formants else { continue }
            let p = point(f1: formants.f1.frequency, f2: formants.f2.frequency)
            let fade = 1 - (end - reading.time) / trailWindow
            context.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)),
                         with: .color(trailColor.opacity(max(0.08, 0.5 * fade))))
        }

        // 지금 점. F1이 불확실하면 속이 빈 점선 원으로 그린다.
        if let current {
            let p = point(f1: current.f1, f2: current.f2)
            let circle = Path(ellipseIn: CGRect(x: p.x - 9, y: p.y - 9, width: 18, height: 18))
            if current.isF1Uncertain {
                context.stroke(circle, with: .color(pointColor), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
            } else {
                context.fill(circle, with: .color(pointColor))
            }
        }
    }

    private func label(_ text: String, bold: Bool = false) -> Text {
        Text(text)
            .font(bold ? .caption2.weight(.semibold) : .caption2)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    VowelChartView(history: PitchHistory(), clock: .frozen(nil), caption: "지금 내는 모음")
        .padding()
}
