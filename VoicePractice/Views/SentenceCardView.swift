import SwiftUI

/// 한국어 연습 문장 카드. 좌우로 밀거나 이전/다음 버튼으로 넘긴다.
/// 직접 쓴 문장, 패턴으로 자동 생성한 문장, 긴 낭독 대본 중에서 고를 수 있다.
struct SentenceCardView: View {
    private enum Source: String, CaseIterable, Identifiable {
        case mine = "내 문장"
        case generated = "자동 생성"
        case scripts = "대본"

        var id: Self { self }
    }

    /// 연습 중인지. 대본의 "들려줄 길이 맞추기"를 잠그는 데 쓴다.
    let isPracticing: Bool

    @AppStorage("sentenceSource") private var source = Source.mine
    @State private var generatedSentences: [String] = []
    @State private var index = 0
    /// 문장 묶음이 바뀔 때마다 늘려서 카드 넘김 상태를 처음부터 다시 그리게 한다.
    @State private var deckID = 0
    /// 넘기는 카드는 높이를 정해 줘야 해서, 문장 글자(title3) 크기 설정에 맞춰 같이 키운다.
    /// 고정 높이였을 때는 아주 큰 글자에서 문장 첫 줄이 잘렸다.
    @ScaledMetric(relativeTo: .title3) private var cardHeight: CGFloat = 120

    private var sentences: [String] {
        source == .mine ? PracticeSentences.all : generatedSentences
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("문장 종류", selection: $source) {
                    ForEach(Source.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)

                if source == .generated {
                    Button {
                        generateSentences()
                    } label: {
                        Label("새 문장", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if source == .scripts {
                ScriptReaderView(isPracticing: isPracticing)
            } else if sentences.isEmpty {
                Text("연습 문장이 없어요. PracticeSentences.swift에 문장을 추가해 주세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                cards
            }
        }
        .onAppear {
            if generatedSentences.isEmpty {
                generateSentences()
            }
        }
        .onChange(of: source) {
            index = 0
            deckID += 1
        }
    }

    private var cards: some View {
        VStack(spacing: 8) {
            TabView(selection: $index) {
                ForEach(sentences.indices, id: \.self) { i in
                    card(for: sentences[i])
                        .padding(.horizontal, 2)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: cardHeight)
            .id(deckID)

            HStack {
                Button {
                    withAnimation { index -= 1 }
                } label: {
                    Label("이전", systemImage: "chevron.left")
                }
                .disabled(index == 0)

                Spacer()
                Text("\(index + 1) / \(sentences.count)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    withAnimation { index += 1 }
                } label: {
                    Label("다음", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .disabled(index == sentences.count - 1)
            }
            .font(.subheadline)
        }
    }

    private func card(for sentence: String) -> some View {
        VStack(spacing: 10) {
            WordWrappedText(text: sentence, textStyle: .title3, weight: .medium, alignment: .center)
            Text(vowelSummary(for: sentence))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func generateSentences() {
        var generator = SystemRandomNumberGenerator()
        generatedSentences = SentenceGenerator().makeDeck(using: &generator).map(\.text)
        index = 0
        deckID += 1
    }

    /// 예: "많이 나오는 모음  아 3 · 이 2"
    private func vowelSummary(for sentence: String) -> String {
        let top = KoreanVowel.mostFrequent(in: sentence)
        guard !top.isEmpty else { return " " }
        return "많이 나오는 모음  " + top.map { "\($0.vowel.rawValue) \($0.count)" }.joined(separator: " · ")
    }
}

/// "다음 >"처럼 아이콘을 글자 오른쪽에 둔다.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon
        }
    }
}

#Preview {
    SentenceCardView(isPracticing: false)
        .padding()
}
