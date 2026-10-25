import Charts
import SwiftData
import SwiftUI

/// 두 녹음 비교: 남긴 녹음 두 개(A·B)를 골라 수치를 나란히 보고, 높이 분포를 겹쳐 보고, 번갈아 듣는다.
/// 어느 쪽이 낫다는 말은 하지 않고 차이만 보여 준다 (원칙 3).
struct RecordingCompareView: View {
    /// 고를 수 있는 녹음 (최근 것부터)
    let recordings: [SavedRecording]
    let archive: PracticeArchive
    /// 연습 중이면 재생을 막는다 (연습과 재생이 같은 마이크·스피커를 쓰므로).
    let audio: AudioInputManager

    @State private var a: SavedRecording?
    @State private var b: SavedRecording?
    @State private var player = ComparePlayer()
    @AppStorage(TargetRangeStore.lowerKey) private var targetLower: Double?
    @AppStorage(TargetRangeStore.upperKey) private var targetUpper: Double?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// A는 내 기준 색(보라), B는 기록 색(초록). 분홍·파랑을 전/후 짝으로 쓰지 않는다 (UllimColor 참고).
    private let colorA = UllimColor.reference
    private let colorB = UllimColor.record

    init(recordings: [SavedRecording], initialA: SavedRecording, initialB: SavedRecording,
         archive: PracticeArchive, audio: AudioInputManager) {
        self.recordings = recordings
        self.archive = archive
        self.audio = audio
        _a = State(initialValue: initialA)
        _b = State(initialValue: initialB)
    }

    private var target: ClosedRange<Double>? {
        guard let targetLower, let targetUpper else { return nil }
        return min(targetLower, targetUpper)...max(targetLower, targetUpper)
    }

    var body: some View {
        NavigationStack {
            Form {
                pickerSection
                if let a, let b {
                    numbersSection(a, b)
                    distributionSection(a, b)
                    listenSection
                }
            }
            .navigationTitle("두 녹음 비교")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
        .task(id: a?.persistentModelID) {
            if let a {
                await player.load(.a, from: archive.fileURL(for: a))
            }
        }
        .task(id: b?.persistentModelID) {
            if let b {
                await player.load(.b, from: archive.fileURL(for: b))
            }
        }
        .onChange(of: audio.isRunning) { _, isRunning in
            if isRunning {
                player.stop()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                player.stop()
            }
        }
        .onDisappear {
            player.stop()
        }
    }

    // MARK: - 고르기

    private var pickerSection: some View {
        Section {
            Picker(selection: $a) {
                ForEach(recordings) { recording in
                    Text(pickerLabel(recording)).tag(Optional(recording))
                }
            } label: {
                sideLabel(.a)
            }
            Picker(selection: $b) {
                ForEach(recordings) { recording in
                    Text(pickerLabel(recording)).tag(Optional(recording))
                }
            } label: {
                sideLabel(.b)
            }
            Button {
                (a, b) = (b, a)
            } label: {
                Label("A와 B 바꾸기", systemImage: "arrow.up.arrow.down")
            }
        } footer: {
            if a != nil, a == b {
                Text("같은 녹음을 골랐어요. 다른 녹음을 골라 보세요.")
            } else {
                Text("처음에는 가장 먼저 남긴 녹음(A)과 가장 최근 녹음(B)을 골라 둬요.")
            }
        }
    }

    /// 앱에서 녹음한 것은 이름에 날짜가 있고, 불러온 파일은 이름 뒤에 날짜를 붙인다.
    private func pickerLabel(_ recording: SavedRecording) -> String {
        recording.title.isEmpty
            ? recording.displayTitle
            : "\(recording.title) · \(recording.recordedAt.formatted(.dateTime.month().day()))"
    }

    private func sideLabel(_ side: ComparePlayer.Side) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color(side))
                .frame(width: 10, height: 10)
            Text(side.rawValue)
                .fontWeight(.semibold)
        }
    }

    private func color(_ side: ComparePlayer.Side) -> Color {
        side == .a ? colorA : colorB
    }

    // MARK: - 나란히

    private func numbersSection(_ a: SavedRecording, _ b: SavedRecording) -> some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Color.clear
                        .gridCellUnsizedAxes([.horizontal, .vertical])
                    sideLabel(.a)
                    sideLabel(.b)
                }
                GridRow {
                    Text("남긴 때")
                        .foregroundStyle(.secondary)
                    dateCell(a.recordedAt)
                    dateCell(b.recordedAt)
                }
                row("말한 언어", a.language.label, b.language.label)
                row("길이", PitchSummary.durationLabel(a.durationSeconds), PitchSummary.durationLabel(b.durationSeconds))
                row("중앙", "\(Int(a.medianHz.rounded())) Hz", "\(Int(b.medianHz.rounded())) Hz")
                row("범위", rangeText(a), rangeText(b))
                row("높낮이 폭", semitoneText(a), semitoneText(b))
                row("그때 목표", targetText(a), targetText(b))
                row("목표 범위 안", percentText(a), percentText(b))
                row("목소리 잡힌 시간", voicedText(a), voicedText(b))
            }
            .font(.footnote)
            Text(RecordingComparison.medianDifferenceText(a: a.medianHz, b: b.medianHz))
                .font(.subheadline)
        } header: {
            Text("나란히 보기")
        } footer: {
            Text("범위는 아래 10%~위 10%, 높낮이 폭은 그 범위를 반음으로 센 값이에요 (클수록 억양의 오르내림이 커요). 목표 범위 안은 각 녹음을 남길 때의 목표 범위로 쟀어요.")
        }
    }

    private func row(_ label: String, _ valueA: String, _ valueB: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(valueA)
                .monospacedDigit()
            Text(valueB)
                .monospacedDigit()
        }
    }

    /// 날짜와 시각을 두 줄로 (한 줄이면 칸이 좁아 잘린다)
    private func dateCell(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(date.formatted(.dateTime.month().day()))
            Text(date.formatted(.dateTime.hour().minute()))
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
    }

    private func rangeText(_ recording: SavedRecording) -> String {
        "\(Int(recording.lowHz.rounded()))–\(Int(recording.highHz.rounded())) Hz"
    }

    private func semitoneText(_ recording: SavedRecording) -> String {
        let semitones = RecordingComparison.rangeSemitones(low: recording.lowHz, high: recording.highHz)
        return "반음 \(String(format: "%.1f", semitones))개"
    }

    private func targetText(_ recording: SavedRecording) -> String {
        recording.target.map { "\(Int($0.lowerBound))–\(Int($0.upperBound)) Hz" } ?? "정하지 않음"
    }

    private func percentText(_ recording: SavedRecording) -> String {
        recording.inTargetFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
    }

    private func voicedText(_ recording: SavedRecording) -> String {
        "\(String(format: "%.1f", recording.voicedSeconds))초"
    }

    // MARK: - 높이 분포

    private func distributionSection(_ a: SavedRecording, _ b: SavedRecording) -> some View {
        Section {
            if !player.loadingSides.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("녹음을 읽는 중…")
                        .foregroundStyle(.secondary)
                }
            } else if let loadedA = player.a, let loadedB = player.b {
                distributionChart(loadedA.voiced, loadedB.voiced)
                    .padding(.vertical, 6)
            }
            ForEach([ComparePlayer.Side.a, .b].filter { player.failedSides.contains($0) }, id: \.self) { side in
                Text("\(side.rawValue)의 소리 파일을 읽지 못했어요. 위의 숫자만 비교할 수 있어요.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("높이 분포")
        } footer: {
            Text("목소리가 잡힌 시간 중 각 높이(반음 반 칸 간격)에 머문 비율이에요. 가로축은 반음 눈금이라 낮은 목소리와 높은 목소리의 흔들림을 같은 기준으로 볼 수 있어요. 점선은 각 녹음의 중앙값, 파란 띠는 지금 목표 범위예요.")
        }
    }

    private func distributionChart(_ voicedA: [Double], _ voicedB: [Double]) -> some View {
        let domain = RecordingComparison.domain(voicedA, voicedB, target: target)
        let binsA = RecordingComparison.distribution(voicedA, in: domain)
        let binsB = RecordingComparison.distribution(voicedB, in: domain)
        let peak = (binsA + binsB).map(\.fraction).max() ?? 0
        let yMax = max(peak * 100 * 1.15, 10)
        return Chart {
            targetBand(yMax: yMax)
            distributionMarks(binsA, side: .a)
            distributionMarks(binsB, side: .b)
            medianRule(voicedA, side: .a)
            medianRule(voicedB, side: .b)
        }
        .chartForegroundStyleScale(["A": colorA, "B": colorB])
        .chartXScale(domain: domain, type: .log)  // 반음 눈금
        .chartXAxis {
            AxisMarks(values: PitchScale.ticks(in: domain))
        }
        .chartYScale(domain: 0...yMax)
        .chartXAxisLabel("Hz")
        .chartYAxisLabel("%")
        .chartLegend(.hidden)
        .frame(height: 200)
    }

    @ChartContentBuilder
    private func targetBand(yMax: Double) -> some ChartContent {
        if let target {
            RectangleMark(
                xStart: .value("목표 하한", target.lowerBound),
                xEnd: .value("목표 상한", target.upperBound),
                yStart: .value("아래", 0.0),
                yEnd: .value("위", yMax)
            )
            .foregroundStyle(UllimColor.target.opacity(UllimColor.bandOpacity))
        }
    }

    @ChartContentBuilder
    private func distributionMarks(_ bins: [RecordingComparison.Bin], side: ComparePlayer.Side) -> some ChartContent {
        ForEach(bins) { bin in
            AreaMark(
                x: .value("높이", bin.center),
                y: .value("비율", bin.fraction * 100),
                series: .value("녹음", side.rawValue),
                stacking: .unstacked
            )
            .foregroundStyle(by: .value("녹음", side.rawValue))
            .opacity(0.15)
            .interpolationMethod(.monotone)
            LineMark(
                x: .value("높이", bin.center),
                y: .value("비율", bin.fraction * 100),
                series: .value("녹음", side.rawValue)
            )
            .foregroundStyle(by: .value("녹음", side.rawValue))
            .interpolationMethod(.monotone)
        }
    }

    @ChartContentBuilder
    private func medianRule(_ voiced: [Double], side: ComparePlayer.Side) -> some ChartContent {
        if !voiced.isEmpty {
            RuleMark(x: .value("중앙값", PitchSummary.percentile(voiced.sorted(), 0.5)))
                .foregroundStyle(color(side))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
    }

    // MARK: - 듣기

    private var canPlay: Bool {
        !audio.isRunning && !audio.isAnalyzingFile
    }

    private var listenSection: some View {
        Section {
            listenButton(.a)
            listenButton(.b)
            Button {
                player.playBoth()
            } label: {
                Label("A → B 이어 듣기", systemImage: "arrow.right")
            }
            .disabled(!canPlay || player.a == nil || player.b == nil)

            if let side = player.playing, let interval = player.playInterval {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(color(side))
                    Text("\(side.rawValue) 듣는 중")
                    Spacer()
                    Text(timerInterval: interval, countsDown: true)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Button("멈추기") {
                        player.stop()
                    }
                    .buttonStyle(.borderless)
                }
                .font(.subheadline)
            }
        } header: {
            Text("듣기")
        } footer: {
            if !canPlay {
                Text("연습을 멈춘 뒤에 들을 수 있어요.")
            } else {
                Text("두 녹음 모두 가장 큰 소리를 같은 크기로 맞춰 들려줘요. 그래서 음량 차이는 비교되지 않아요.")
            }
        }
    }

    private func listenButton(_ side: ComparePlayer.Side) -> some View {
        Button {
            if player.playing == side {
                player.stop()
            } else {
                player.play(side)
            }
        } label: {
            HStack {
                Label {
                    Text("\(side.rawValue) 듣기")
                } icon: {
                    Image(systemName: player.playing == side ? "stop.fill" : "play.fill")
                        .foregroundStyle(color(side))
                }
                Spacer()
                if let loaded = player[side] {
                    Text(PitchSummary.durationLabel(loaded.duration))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(color(side))
        .disabled(!canPlay || player[side] == nil)
    }
}
