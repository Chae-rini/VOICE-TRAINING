import Charts
import SwiftUI

/// [기록] 탭의 그래프 세 개: 연습마다 목소리 높이(중앙값 점 + 아래 10%~위 10% 세로줄), 연습마다 공명 밝기(F2 중앙값 점,
/// 읽은 대본을 고르면 그 대본을 읽은 녹음마다), 날마다 연습한 시간(막대).
/// 점은 목소리 색(분홍), 파란 띠는 지금 목표 범위, 보라 점선은 지금 기준(목소리 높이·F2), 막대는 기록 색(초록)이다 ([높이] 탭과 같은 색).
/// 언어는 색이 아니라 점 모양으로 나눈다 (색은 역할마다 하나씩만 쓰려고). 높이·F2 축은 반음 눈금이다.
/// 좋아졌다·나빠졌다 같은 판정은 하지 않고 숫자의 흐름만 보여 준다.
struct HistoryChartView: View {
    let points: [SessionPoint]
    let daily: [DailyPractice]
    let dateDomain: ClosedRange<Date>
    let pitchDomain: ClosedRange<Double>
    let target: ClosedRange<Double>?
    let baseline: Double?
    /// [Hz] 공명 밝기 그래프의 세로축
    let resonanceDomain: ClosedRange<Double>
    /// [Hz] 지금 기준 F2 (내 목소리 재기 때 저장). 없으면 점선을 그리지 않는다
    let baselineF2: Double?
    /// 대본을 읽은 녹음들 (기간·언어로 거른 것). 공명 밝기 그래프에서 같은 대본만 골라 볼 때 쓴다
    var scriptTakes: [ScriptTakePoint] = []

    /// 공명 밝기 그래프에서 고른 대본. nil이면 모든 연습
    @State private var scriptID: String?

    /// 그래프에 나온 언어만 범례에 넣는다.
    private var languages: [PracticeLanguage] {
        PracticeLanguage.allCases.filter { language in
            points.contains { $0.language == language } || scriptTakes.contains { $0.language == language }
        }
    }

    /// 공명 밝기 점 하나: 연습 한 번(모든 연습) 또는 고른 대본을 읽은 녹음 한 번
    private struct ResonanceDot: Identifiable {
        let id: Date
        let f2: Double
        let language: PracticeLanguage
    }

    private var scriptChoices: [ScriptChoice] {
        PracticeHistory.scriptChoices(scriptTakes)
    }

    /// 고른 대본. 기간·언어를 바꿔 그 대본을 읽은 녹음이 없어지면 nil(모든 연습)
    private var activeChoice: ScriptChoice? {
        scriptChoices.first { $0.id == scriptID }
    }

    private var chosenTakes: [ScriptTakePoint] {
        guard let activeChoice else { return [] }
        return scriptTakes.filter { $0.script.id == activeChoice.id }
    }

    /// 모든 연습이면 F2 중앙값이 남은 연습만 (2026-10-25 전의 연습과 포먼트를 충분히 못 잡은 연습은 빠진다)
    private var resonanceDots: [ResonanceDot] {
        if activeChoice != nil {
            return chosenTakes.map { ResonanceDot(id: $0.endedAt, f2: $0.f2, language: $0.language) }
        }
        return points.compactMap { point in
            point.f2.map { ResonanceDot(id: point.startedAt, f2: $0, language: point.language) }
        }
    }

    private var shownResonanceDomain: ClosedRange<Double> {
        activeChoice == nil ? resonanceDomain : PracticeHistory.resonanceDomain(chosenTakes, baseline: baselineF2)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            pitchChart
            resonanceChart
            practiceChart
        }
    }

    private var pitchChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("연습마다 목소리 높이 (Hz)")
                .font(.subheadline.weight(.semibold))
            Chart {
                if let target {
                    RectangleMark(
                        xStart: .value("시작", dateDomain.lowerBound),
                        xEnd: .value("끝", dateDomain.upperBound),
                        yStart: .value("목표 하한", target.lowerBound),
                        yEnd: .value("목표 상한", target.upperBound)
                    )
                    .foregroundStyle(UllimColor.target.opacity(UllimColor.bandOpacity))
                }
                if let baseline {
                    RuleMark(y: .value("기준", baseline))
                        .foregroundStyle(UllimColor.reference)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("기준")
                                .font(.caption2)
                                .foregroundStyle(UllimColor.reference)
                        }
                }
                ForEach(points) { point in
                    RuleMark(
                        x: .value("날짜", point.startedAt),
                        yStart: .value("아래 10%", point.low),
                        yEnd: .value("위 10%", point.high)
                    )
                    .foregroundStyle(UllimColor.voice.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    PointMark(
                        x: .value("날짜", point.startedAt),
                        y: .value("중앙값", point.median)
                    )
                    .foregroundStyle(UllimColor.voice)
                    .symbol(by: .value("언어", point.language.label))
                    .symbolSize(44)
                }
            }
            .chartSymbolScale(domain: languages.map(\.label), range: languages.map(\.chartSymbol))
            .chartXScale(domain: dateDomain)
            // 세로축은 [높이] 탭과 같은 반음 눈금 (로그 눈금 = 같은 반음 폭이 같은 길이)
            .chartYScale(domain: pitchDomain, type: .log)
            .chartYAxis {
                AxisMarks(values: PitchScale.ticks(in: pitchDomain))
            }
            .chartXAxis { dateAxis }
            // 기본 범례는 강조색(파랑)으로 그려져 분홍 점과 어긋나므로 직접 그린다.
            .chartLegend(.hidden)
            .frame(height: 220)
            if languages.count > 1 {
                languageLegend
            }
            Text("점은 연습 한 번의 중앙값, 세로줄은 아래 10%~위 10%예요. 파란 띠는 지금 목표 범위, 보라 점선은 지금 기준 목소리예요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                // 목록 줄 안에서는 높이가 모자라 “…”로 잘릴 때가 있어 줄을 다 펼친다
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 공명 밝기(F2)는 내 기준과만 견준다. 성별 평균 같은 바깥 기준은 쓰지 않는다 (원칙 3).
    /// 문장 속 F2는 말한 모음에 따라 달라지므로 같은 대본을 읽은 연습끼리 견줘야 한다는 안내를 빼지 않는다 ([높이] 공명 막대와 같은 안내).
    /// 읽은 대본이 남은 녹음이 있으면 대본 하나를 골라 그 대본을 읽은 녹음만 그린다 (2026-11-03~).
    private var resonanceChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(activeChoice == nil ? "연습마다 공명 밝기 (F2, Hz)" : "같은 대본을 읽은 녹음마다 공명 밝기 (F2, Hz)")
                .font(.subheadline.weight(.semibold))
            if !scriptChoices.isEmpty {
                scriptPicker
            }
            if resonanceDots.isEmpty {
                Text("이 기간의 연습에는 공명 밝기 기록이 없어요. 공명 밝기는 이 기능이 생긴 뒤의 연습부터 남고, 목소리의 공명이 충분히 잡히지 않은 연습은 빠져요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Chart {
                    if let baselineF2 {
                        RuleMark(y: .value("기준 F2", baselineF2))
                            .foregroundStyle(UllimColor.reference)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("기준")
                                    .font(.caption2)
                                    .foregroundStyle(UllimColor.reference)
                            }
                    }
                    ForEach(resonanceDots) { dot in
                        PointMark(
                            x: .value("날짜", dot.id),
                            y: .value("F2 중앙값", dot.f2)
                        )
                        .foregroundStyle(UllimColor.voice)
                        .symbol(by: .value("언어", dot.language.label))
                        .symbolSize(44)
                    }
                }
                .chartSymbolScale(domain: languages.map(\.label), range: languages.map(\.chartSymbol))
                .chartXScale(domain: dateDomain)
                // [높이] 공명 막대와 같은 반음 눈금 (같은 비율의 차이가 같은 길이)
                .chartYScale(domain: shownResonanceDomain, type: .log)
                .chartYAxis {
                    AxisMarks(values: PitchScale.formantTicks(in: shownResonanceDomain)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            // 앱의 다른 F2 숫자처럼 쉼표 없이 (기본은 "1,500", Text("\(…)")도 쉼표를 넣는다)
                            if let hz = value.as(Double.self) {
                                Text(verbatim: String(Int(hz)))
                            }
                        }
                    }
                }
                .chartXAxis { dateAxis }
                .chartLegend(.hidden)
                .frame(height: 160)
                Text(resonanceNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 대본 고르기. 많이 읽은 대본부터, 녹음 수를 함께 보인다
    private var scriptPicker: some View {
        HStack {
            Text("읽은 대본")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Picker("읽은 대본", selection: $scriptID) {
                Text("모든 연습").tag(String?.none)
                ForEach(scriptChoices) { choice in
                    Text("\(choice.script.title) · \(choice.takeCount)번").tag(String?.some(choice.id))
                }
            }
            .pickerStyle(.menu)
            // 이름은 왼쪽 글자로 보이므로 고르기 단추에는 고른 값만 (최신 iOS는 메뉴 고르기에도 이름을 함께 그린다)
            .labelsHidden()
        }
    }

    private var resonanceNote: String {
        guard let activeChoice else {
            let base = "점은 연습 한 번의 F2 중앙값이에요. 위쪽이 밝은 쪽이고, 보라 점선은 지금 기준이에요. F2는 말한 모음에 따라 달라져서, 같은 대본을 읽은 연습끼리 비교해야 정확해요."
            return base + (scriptChoices.isEmpty
                ? " [높이]에서 대본을 읽으며 연습하면 같은 대본을 읽은 녹음끼리 골라 볼 수 있어요."
                : " ‘읽은 대본’에서 하나를 고르면 그 대본을 읽은 녹음만 보여요.")
        }
        // 제목 뒤 조사가 받침에 따라 달라지지 않게 ‘대본’에 조사를 붙인다
        return "점은 ‘\(activeChoice.script.title)’ 대본을 읽은 녹음 한 번의 F2 중앙값이에요(녹음 \(activeChoice.takeCount)개). 같은 글이라 점끼리 견줄 수 있어요. 보라 점선은 지금 기준인데, 기준은 다른 글로 쟀을 수 있어서 참고로만 보세요."
    }

    /// 언어별 점 모양 (그래프의 점과 같은 분홍)
    private var languageLegend: some View {
        HStack(spacing: 12) {
            ForEach(languages) { language in
                HStack(spacing: 4) {
                    Image(systemName: language.symbolName)
                        .font(.system(size: 8))
                        .foregroundStyle(UllimColor.voice)
                    Text(language.label)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.caption)
    }

    private var practiceChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("날마다 연습한 시간 (분)")
                .font(.subheadline.weight(.semibold))
            Chart(daily) { day in
                BarMark(
                    x: .value("날", day.day, unit: .day),
                    y: .value("분", day.minutes)
                )
                .foregroundStyle(UllimColor.record.opacity(0.8))
            }
            .chartXScale(domain: dateDomain)
            .chartXAxis { dateAxis }
            .frame(height: 110)
        }
    }

    private var dateAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
            AxisGridLine()
            AxisTick()
            AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
        }
    }
}

extension PracticeLanguage {
    /// 그래프에서 언어를 구분하는 점 모양. 색은 모두 목소리 색(분홍)이다.
    var chartSymbol: BasicChartSymbolShape {
        switch self {
        case .korean: .circle
        case .english: .square
        case .japanese: .triangle
        case .other: .diamond
        }
    }

    /// 목록의 언어 표시에 쓰는 같은 모양의 SF Symbol
    var symbolName: String {
        switch self {
        case .korean: "circle.fill"
        case .english: "square.fill"
        case .japanese: "triangle.fill"
        case .other: "diamond.fill"
        }
    }
}

#Preview {
    let now = Date.now
    let points: [SessionPoint] = (0..<12).map { (day: Int) -> SessionPoint in
        let start: Date = now.addingTimeInterval(-2 * 86_400 * Double(day))
        let median: Double = 160 + 8 * Double(day % 4)
        let language: PracticeLanguage = day % 3 == 0 ? .english : .korean
        return SessionPoint(startedAt: start, practiceSeconds: 300 + 60 * Double(day),
                            median: median, low: median - 16, high: median + 16, language: language,
                            f2: day > 9 ? nil : 1500 + 25 * Double(day % 5))
    }
    let script = TakeScript(id: "preview", title: "새벽 첫차")
    let scriptTakes = (0..<6).map { (day: Int) -> ScriptTakePoint in
        ScriptTakePoint(endedAt: now.addingTimeInterval(-3 * 86_400 * Double(day)), script: script,
                        f2: 1480 + 15 * Double(day % 3), language: .korean)
    }
    let calendar = Calendar.current
    return HistoryChartView(
        points: points,
        daily: PracticeHistory.dailyPractice(points, calendar: calendar),
        dateDomain: PracticeHistory.dateDomain(points, period: .month, now: now, calendar: calendar),
        pitchDomain: PracticeHistory.pitchDomain(points, target: 150...190, baseline: 165),
        target: 150...190,
        baseline: 165,
        resonanceDomain: PracticeHistory.resonanceDomain(points, baseline: 1520),
        baselineF2: 1520,
        scriptTakes: scriptTakes
    )
    .padding()
}
