import Charts
import SwiftUI

/// [기록] 탭의 그래프 세 개: 연습마다 목소리 높이(중앙값 점 + 아래 10%~위 10% 세로줄), 연습마다 공명 밝기(F2 중앙값 점),
/// 날마다 연습한 시간(막대).
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

    /// 그래프에 나온 언어만 범례에 넣는다.
    private var languages: [PracticeLanguage] {
        PracticeLanguage.allCases.filter { language in points.contains { $0.language == language } }
    }

    /// F2 중앙값이 남은 연습만 (2026-10-25 전의 연습과 포먼트를 충분히 못 잡은 연습은 빠진다)
    private var resonancePoints: [(point: SessionPoint, f2: Double)] {
        points.compactMap { point in point.f2.map { (point, $0) } }
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
        }
    }

    /// 공명 밝기(F2)는 내 기준과만 견준다. 성별 평균 같은 바깥 기준은 쓰지 않는다 (원칙 3).
    /// 문장 속 F2는 말한 모음에 따라 달라지므로 같은 대본을 읽은 연습끼리 견줘야 한다는 안내를 빼지 않는다 ([높이] 공명 막대와 같은 안내).
    private var resonanceChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("연습마다 공명 밝기 (F2, Hz)")
                .font(.subheadline.weight(.semibold))
            if resonancePoints.isEmpty {
                Text("이 기간의 연습에는 공명 밝기 기록이 없어요. 공명 밝기는 이 기능이 생긴 뒤의 연습부터 남고, 목소리의 공명이 충분히 잡히지 않은 연습은 빠져요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    ForEach(resonancePoints, id: \.point.id) { item in
                        PointMark(
                            x: .value("날짜", item.point.startedAt),
                            y: .value("F2 중앙값", item.f2)
                        )
                        .foregroundStyle(UllimColor.voice)
                        .symbol(by: .value("언어", item.point.language.label))
                        .symbolSize(44)
                    }
                }
                .chartSymbolScale(domain: languages.map(\.label), range: languages.map(\.chartSymbol))
                .chartXScale(domain: dateDomain)
                // [높이] 공명 막대와 같은 반음 눈금 (같은 비율의 차이가 같은 길이)
                .chartYScale(domain: resonanceDomain, type: .log)
                .chartYAxis {
                    AxisMarks(values: PitchScale.formantTicks(in: resonanceDomain)) { value in
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
                Text("점은 연습 한 번의 F2 중앙값이에요. 위쪽이 밝은 쪽이고, 보라 점선은 지금 기준이에요. F2는 말한 모음에 따라 달라져서, 같은 대본을 읽은 연습끼리 비교해야 정확해요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
    let calendar = Calendar.current
    return HistoryChartView(
        points: points,
        daily: PracticeHistory.dailyPractice(points, calendar: calendar),
        dateDomain: PracticeHistory.dateDomain(points, period: .month, now: now, calendar: calendar),
        pitchDomain: PracticeHistory.pitchDomain(points, target: 150...190, baseline: 165),
        target: 150...190,
        baseline: 165,
        resonanceDomain: PracticeHistory.resonanceDomain(points, baseline: 1520),
        baselineF2: 1520
    )
    .padding()
}
