import SwiftUI

/// [모음] 탭: 실시간 모음 지도, 내 모음 지도 재기, 보는 법.
/// 녹음·듣기 조작은 [높이] 탭과 같은 아래 영역을 함께 쓴다.
struct VowelMapScreen: View {
    let audio: AudioInputManager
    /// 지도 위 숫자 아래의 안내 문구
    let caption: String
    /// 파일 앱에서 녹음을 골라 이 모음으로 잰다.
    let onImportVowel: (KoreanVowel) -> Void

    @AppStorage(VowelMap.storageKey) private var mapData: Data?
    @AppStorage("selectedVowel") private var selectedName = KoreanVowel.a.rawValue
    /// 방금 잰 결과 안내
    @State private var message: String?
    /// 저장하지 못한 안내인지 (색을 다르게)
    @State private var messageIsWarning = false

    private var map: VowelMap {
        VowelMap(data: mapData)
    }

    private var selected: KoreanVowel {
        KoreanVowel(rawValue: selectedName) ?? .a
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VowelChartView(history: audio.history, clock: audio.graphClock, caption: caption,
                               map: map, selected: selected)
                myMapSection
                guide
            }
            .padding()
        }
        // 모음 하나를 다 재면 저장한다 (기기 안에만). 지도에는 마지막 값, 이력에는 잴 때마다 하나씩.
        .onChange(of: audio.vowelResult) { _, result in
            guard let result else { return }
            if let entry = result.entry {
                var updated = map
                updated.set(entry, for: result.vowel)
                mapData = updated.data
                audio.archive.saveVowel(entry, for: result.vowel)
                message = "‘\(result.vowel.rawValue)’를 저장했어요 · F1 \(Int(entry.f1.rounded())) · F2 \(Int(entry.f2.rounded())) Hz"
                messageIsWarning = false
            } else {
                message = "목소리가 너무 짧게 잡혔어요. ‘\(result.vowel.rawValue)’를 3초 동안 끊지 말고 길게 내 보세요."
                messageIsWarning = true
            }
            audio.clearVowelResult()
        }
    }

    private var myMapSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("내 모음 지도")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(map.measuredCount)/7개 잼")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text("모음을 고르고 3초 동안 길게 내면 지도에 내 위치로 남아요. 다시 재면 새 값으로 바뀌어요.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                ForEach(KoreanVowel.allCases, id: \.self) { vowel in
                    Button {
                        selectedName = vowel.rawValue
                        message = nil
                    } label: {
                        VStack(spacing: 2) {
                            Text(vowel.rawValue)
                                .font(.headline)
                            Image(systemName: map[vowel] == nil ? "circle" : "checkmark.circle.fill")
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .tint(vowel == selected ? UllimColor.reference : UllimColor.inactive)
                    .accessibilityLabel("\(vowel.rawValue)\(map[vowel] == nil ? "" : ", 잼")")
                }
            }

            // 내 모음 지도는 내 기준이라 재기 버튼도 보라(지도의 원과 같은 색)
            HStack(spacing: 10) {
                Button {
                    message = nil
                    Task { await audio.measureVowel(selected) }
                } label: {
                    Label("‘\(selected.rawValue)’ 재기 · 3초", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(audio.isRunning || audio.isAnalyzingFile || audio.permission == .denied)

                Button {
                    message = nil
                    onImportVowel(selected)
                } label: {
                    Label("파일로", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .disabled(audio.isRunning || audio.isAnalyzingFile)
            }
            .tint(UllimColor.reference)

            if audio.isAnalyzingFile {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("녹음을 분석하는 중…")
                }
                .font(.footnote)
            } else if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(messageIsWarning ? Color.orange : UllimColor.record)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("모음 지도 보는 법")
                .font(.subheadline.weight(.semibold))
            Text("목과 입안이 울리는 두 주파수(포먼트)로 지금 내는 모음의 위치를 보여 줘요. ‘아·에·이·오·우·으·어’ 중 하나를 2~3초 길게 내 보세요.")
            Text("• 가로(F2): 혀가 앞쪽일수록 왼쪽, 뒤쪽일수록 오른쪽")
            Text("• 세로(F1): 입을 좁게 열수록 위, 크게 열수록 아래")
            Text("• 분홍 점은 지금 내는 소리, 보라 원은 내가 잰 모음이에요. 위에서 고른 모음을 쟀으면 지금 소리와의 차이가 숫자로 나와요.")
            Text("같은 모음도 사람마다 위치가 달라서, 정해진 정답 위치는 없어요. 목소리가 높을수록 세로(F1)는 덜 정확하고 가로(F2)가 더 믿을 만해요. 이때는 점이 속이 빈 점선 원으로 바뀌어요.")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
