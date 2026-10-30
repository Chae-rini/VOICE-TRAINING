import SwiftUI
import UniformTypeIdentifiers

/// "내 목소리 재기": 문장이나 대본을 편하게 읽는 10초로 기준 목소리를 잰다. 읽을 글은 열 때마다 무작위다 (`BaselineReading`).
/// 결과는 중앙값과 범위만 보여 주고, 높다·낮다 같은 평가는 하지 않는다.
/// 저장하면 그래프에 기준선(점선)이 생기고, 원하면 목표 범위를 기준 ±20 Hz로 맞춘다.
struct BaselineMeasureView: View {
    let audio: AudioInputManager

    @Environment(\.dismiss) private var dismiss
    /// 목표 범위를 기준에 맞출지. 저장해 둔 목표 범위가 있으면 처음에는 꺼 둔다 (저절로 바뀌지 않게).
    @State private var applyToTarget = TargetRangeStore.shouldApplyInitialTarget(in: .standard)
    @State private var isImporting = false
    /// ‘이 값으로 저장’이 실패했는지
    @State private var saveFailed = false
    /// 이번에 읽을 글. 화면을 열 때마다 무작위로 고르고 ‘다른 대본’으로 바꾼다
    @State private var reading = BaselineReading.random()

    private var isMeasuring: Bool {
        audio.loop.phase == .measuring
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("평소에 편하게 말하는 목소리를 재요. 이 높이를 기준으로 목표 범위를 정할 수 있어요.")
                        .foregroundStyle(.secondary)
                    if let saved = TargetRangeStore.savedBaseline(in: .standard), audio.measurement == nil, !isMeasuring {
                        Text("지금 저장된 기준: \(Int(saved.median.rounded())) Hz")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    sentenceCard
                    content
                }
                .padding()
            }
            .navigationTitle("내 목소리 재기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(audio.measurement == nil ? "나중에" : "닫기") {
                        close()
                    }
                }
            }
        }
        // 내 기준 목소리를 재는 화면이라 버튼·스위치를 내 기준 색(보라)으로
        .tint(UllimColor.reference)
        .interactiveDismissDisabled(isMeasuring)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result {
                Task { await audio.measureBaseline(fromFile: url) }
            }
        }
    }

    private var sentenceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reading.instruction)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let title = reading.title {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            WordWrappedText(text: reading.text, textStyle: reading.isSentence ? .title3 : .body,
                            weight: .medium, lineSpacing: reading.isSentence ? 0 : 6)
            // 재는 중이거나 결과가 있을 때는 바꾸지 않는다 (어떤 글로 잰 결과인지 헷갈리지 않게)
            Button {
                reading = BaselineReading.random(excluding: reading)
            } label: {
                Label("다른 대본", systemImage: "shuffle")
            }
            .font(.subheadline)
            .disabled(isMeasuring || audio.isAnalyzingFile || audio.measurement != nil)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var content: some View {
        if isMeasuring {
            measuringView
        } else if audio.isAnalyzingFile {
            HStack(spacing: 8) {
                ProgressView()
                Text("녹음을 분석하는 중…")
            }
        } else if let measurement = audio.measurement {
            switch measurement {
            case .tooLittleVoice:
                tooLittleVoiceView
            case .measured(let baseline):
                resultView(baseline)
            }
        } else {
            startButtons
        }
    }

    private var startButtons: some View {
        VStack(spacing: 10) {
            Button {
                Task { await audio.measureBaseline() }
            } label: {
                Label("10초 재기", systemImage: "mic.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(UllimColor.referenceFill)
            .controlSize(.large)
            .disabled(audio.isRunning || audio.permission == .denied)

            Button {
                isImporting = true
            } label: {
                Label("녹음 파일로 재기", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(audio.isRunning)

            if audio.permission == .denied {
                Text("마이크 권한이 꺼져 있어 녹음 파일로만 잴 수 있어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if audio.isRunning {
                Text("연습 중에는 잴 수 없어요. 연습을 멈춘 뒤 다시 눌러 주세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let message = audio.errorMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var measuringView: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(audio.currentFrequency.map { "\(Int($0.rounded()))" } ?? "–")
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("Hz")
                    .foregroundStyle(.secondary)
            }
            if let interval = audio.phaseInterval {
                ProgressView(timerInterval: interval, countsDown: true) {
                    Text("녹음 중")
                }
            }
            Button("그만두기", role: .cancel) {
                audio.stop()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var tooLittleVoiceView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("목소리가 거의 잡히지 않았어요.", systemImage: "exclamationmark.circle")
                .font(.headline)
            Text(reading.isSentence
                 ? "조용한 곳에서 위 문장을 평소 목소리로 소리 내어 다시 읽어 주세요."
                 : "조용한 곳에서 위 대본을 평소 목소리로 소리 내어 처음부터 다시 읽어 주세요.")
                .foregroundStyle(.secondary)
            Button("다시 재기") {
                audio.clearMeasurement()
            }
            .buttonStyle(.borderedProminent)
            .tint(UllimColor.referenceFill)
        }
    }

    private func resultView(_ baseline: VoiceBaseline) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("잰 결과")
                .font(.headline)
            HStack(spacing: 0) {
                stat("중앙", "\(Int(baseline.median.rounded())) Hz")
                stat("범위", "\(Int(baseline.low.rounded()))–\(Int(baseline.high.rounded())) Hz")
            }
            Text("범위는 잡힌 높이 중 아래 10%~위 10% 사이예요.")
                .font(.caption)
                .foregroundStyle(.secondary)
            // 공명 밝기 막대의 가운데(기준)로 함께 저장한다.
            // F2는 읽은 모음에 따라 달라서, 잴 때마다 글이 바뀌면 기준도 조금 흔들린다
            Text(baseline.f2.map { "공명 밝기 기준(F2 중앙값): \(Int($0.rounded())) Hz. 읽은 글의 모음에 따라 조금 달라질 수 있어요." }
                 ?? "포먼트가 충분히 잡히지 않아 공명 밝기 기준은 저장하지 않아요.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(isOn: $applyToTarget) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("목표 범위를 이 기준에 맞추기")
                    Text(targetChangeDescription(baseline))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                // 날짜별 이력을 먼저 남긴다. 실패하면 기준·목표 범위도 바꾸지 않고 안내만 한다.
                do {
                    try audio.archive.saveBaseline(baseline)
                } catch {
                    saveFailed = true
                    return
                }
                TargetRangeStore.save(baseline, applyingTarget: applyToTarget, in: .standard)
                audio.clearMeasurement()
                dismiss()
            } label: {
                Text("이 값으로 저장")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(UllimColor.referenceFill)
            .controlSize(.large)

            if saveFailed {
                Label("기록을 저장하지 못했어요. 저장 공간을 확인해 주세요.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Button("다시 재기") {
                saveFailed = false
                audio.clearMeasurement()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func targetChangeDescription(_ baseline: VoiceBaseline) -> String {
        let new = baseline.initialTarget
        let newText = "\(Int(new.lowerBound))–\(Int(new.upperBound)) Hz"
        if let current = TargetRangeStore.savedTarget(in: .standard) {
            let currentText = "\(Int(current.lowerBound))–\(Int(current.upperBound)) Hz"
            return applyToTarget ? "지금 \(currentText) → \(newText)" : "지금 목표 범위(\(currentText))를 그대로 둬요"
        }
        return applyToTarget
            ? "\(newText)로 시작해요. 슬라이더로 위든 아래든 옮길 수 있어요."
            : "목표 범위 없이 기준만 저장해요"
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func close() {
        if isMeasuring {
            audio.stop()
        }
        audio.clearMeasurement()
        dismiss()
    }
}
