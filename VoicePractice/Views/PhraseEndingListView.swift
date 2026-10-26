import SwiftUI

/// 요약 카드 안의 구절별 문장 끝: 요약 한 줄, 숫자 몇 줄, 안내 문구, 펼치면 구절 목록.
/// 글은 `Models/PhraseEndingText.swift`가 만든다. 색에만 기대지 않게 화살표와 이름을 같이 쓴다.
struct PhraseEndingSection: View {
    let analysis: PhraseEndingAnalysis
    /// [s] 녹음의 첫 샘플 시각. 구절 시작을 녹음 처음부터의 시간(0:03)으로 보여 준다
    let takeStart: TimeInterval

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            Text(analysis.headline)
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            ForEach(analysis.detailLines, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !analysis.phrases.isEmpty {
                Text(analysis.guidance)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)

                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("구절 중앙값 → 끝 \(PhraseEndingAnalysis.number(analysis.rules.endWindowSeconds))초 중앙값")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ForEach(Array(analysis.phrases.enumerated()), id: \.offset) { index, phrase in
                            PhraseEndingRow(number: index + 1, phrase: phrase, startOffset: phrase.startTime - takeStart)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("구절별로 보기 (\(analysis.phrases.count)개)")
                        .font(.subheadline)
                }
            }
        }
    }
}

/// 구절 한 줄. 예: "↘ 3. 내려감   182 → 158 Hz" / "0:07 · 2.4반음 내려감 · 바닥 150 Hz · 목표 하한 아래"
private struct PhraseEndingRow: View {
    let number: Int
    let phrase: PhraseEnding
    /// [s] 녹음 처음부터 이 구절이 시작한 때
    let startOffset: TimeInterval

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: phrase.endType.symbolName)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(phrase.endType.color)
                .frame(minWidth: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        title
                        Spacer(minLength: 8)
                        pitch
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        title
                        pitch
                    }
                }
                Text(([GraphWindow.timeLabel(startOffset), phrase.dropLabel] + phrase.notes).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: some View {
        Text("\(number). \(phrase.endType.label)")
            .font(.subheadline.weight(.medium))
    }

    private var pitch: some View {
        Text(phrase.pitchLine)
            .font(.subheadline)
            .monospacedDigit()
    }
}

extension PhraseEndType {
    /// 끝이 움직인 방향의 화살표
    var symbolName: String {
        switch self {
        case .rise: "arrow.up.right"
        case .stable: "arrow.right"
        case .falling: "arrow.down.right"
        case .dropping: "arrow.down"
        }
    }

    /// 종류별 색: 안정은 회색, 올라감은 청록, 내려감은 연한 주황, 크게 내려감은 주황.
    /// 하강 폭 순서(올라감 < 안정 < 내려감 < 크게 내려감)를 안정을 가운데 둔 두 갈래 색으로 보인다.
    /// 분홍·파랑은 쓰지 않는다 (역할 색과 섞이지 않게, 원칙 3). 빨강은 녹음 중 표시라 쓰지 않는다.
    var color: Color {
        switch self {
        case .rise: .teal
        case .stable: UllimColor.inactive
        case .falling: .orange.opacity(0.6)
        case .dropping: .orange
        }
    }
}
