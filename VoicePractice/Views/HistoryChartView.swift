import Charts
import SwiftUI

/// [기록] 탭의 그래프 두 개: 연습마다 목소리 높이(중앙값 점 + 아래 10%~위 10% 세로줄), 날마다 연습한 시간(막대).
/// 청록 띠는 지금 목표 범위, 남보라 점선은 지금 기준 목소리다 ([높이] 탭과 같은 색).
/// 좋아졌다·나빠졌다 같은 판정은 하지 않고 숫자의 흐름만 보여 준다.
struct HistoryChartView: View {
    let points: [SessionPoint]
    let daily: [DailyPractice]
    let dateDomain: ClosedRange<Date>
    let pitchDomain: ClosedRange<Double>
    let target: ClosedRange<Double>?
    let baseline: Double?

    /// 그래프에 나온 언어만 범례에 넣는다.
    private var languages: [PracticeLanguage] {
        PracticeLanguage.allCases.filter { language in points.contains { $0.language == language } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            pitchChart
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
                    .foregroundStyle(Color.teal.opacity(0.12))
                }
                if let baseline {
                    RuleMark(y: .value("기준", baseline))
                        .foregroundStyle(Color.indigo)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("기준")
                                .font(.caption2)
                                .foregroundStyle(Color.indigo)
                        }
                }
                ForEach(points) { point in
                    RuleMark(
                        x: .value("날짜", point.startedAt),
                        yStart: .value("아래 10%", point.low),
                        yEnd: .value("위 10%", point.high)
                    )
                    .foregroundStyle(by: .value("언어", point.language.label))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .opacity(0.35)
                    PointMark(
                        x: .value("날짜", point.startedAt),
                        y: .value("중앙값", point.median)
                    )
                    .foregroundStyle(by: .value("언어", point.language.label))
                    .symbolSize(40)
                }
            }
            .chartForegroundStyleScale(domain: languages.map(\.label), range: languages.map(\.color))
            .chartXScale(domain: dateDomain)
            .chartYScale(domain: pitchDomain)
            .chartXAxis { dateAxis }
            .chartLegend(languages.count > 1 ? .visible : .hidden)
            .frame(height: 220)
            Text("점은 연습 한 번의 중앙값, 세로줄은 아래 10%~위 10%예요. 청록 띠는 지금 목표 범위, 점선은 지금 기준 목소리예요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
                .foregroundStyle(Color.teal.opacity(0.7))
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
    /// 그래프에서 언어를 구분하는 색. 남보라(내 기준)와 겹치지 않게 고른다.
    var color: Color {
        switch self {
        case .korean: .teal
        case .english: .orange
        case .japanese: .green
        case .other: .gray
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
                            median: median, low: median - 16, high: median + 16, language: language)
    }
    let calendar = Calendar.current
    return HistoryChartView(
        points: points,
        daily: PracticeHistory.dailyPractice(points, calendar: calendar),
        dateDomain: PracticeHistory.dateDomain(points, period: .month, now: now, calendar: calendar),
        pitchDomain: PracticeHistory.pitchDomain(points, target: 150...190, baseline: 165),
        target: 150...190,
        baseline: 165
    )
    .padding()
}
