import SwiftData
import SwiftUI

/// [기록] 탭: 기간·언어를 골라 연습의 흐름(그래프)을 보고, 남긴 녹음·연습 기록·내 목소리 재기 이력을 살펴본다.
/// 모든 기록은 이 기기 안에만 있다. 점수·향상률·연속 기록은 보여 주지 않는다.
struct HistoryScreen: View {
    let audio: AudioInputManager
    /// 남긴 녹음을 [높이] 탭에서 재생한다.
    let onPlay: (SavedRecording) -> Void

    @Query(sort: \PracticeSession.startedAt) private var sessions: [PracticeSession]
    @Query(sort: \SavedRecording.recordedAt, order: .reverse) private var recordings: [SavedRecording]
    @Query(sort: \BaselineRecord.measuredAt, order: .reverse) private var baselines: [BaselineRecord]

    @AppStorage(HistoryPeriod.storageKey) private var period = HistoryPeriod.month
    @AppStorage(TargetRangeStore.lowerKey) private var targetLower: Double?
    @AppStorage(TargetRangeStore.upperKey) private var targetUpper: Double?
    @AppStorage(TargetRangeStore.baselineMedianKey) private var baselineMedian: Double?
    @AppStorage(TargetRangeStore.baselineF2Key) private var baselineF2: Double?
    /// nil이면 모든 언어
    @State private var language: PracticeLanguage?
    @State private var isConfirmingDeleteAll = false
    @State private var comparePair: ComparePair?
    @State private var isShowingReminder = false
    /// 지우기가 영구 저장에 실패했는지 (실패하면 기록은 그대로 남는다)
    @State private var deleteFailed = false
    @AppStorage(PracticeReminder.enabledKey) private var isReminderEnabled = false

    private let calendar = Calendar.current

    /// 두 녹음 비교 화면을 처음 열 때 고를 A·B
    private struct ComparePair: Identifiable {
        let id = UUID()
        let a: SavedRecording
        let b: SavedRecording
    }

    private var target: ClosedRange<Double>? {
        guard let targetLower, let targetUpper else { return nil }
        return min(targetLower, targetUpper)...max(targetLower, targetUpper)
    }

    private func isShown(_ date: Date, _ recordLanguage: PracticeLanguage? = nil) -> Bool {
        period.contains(date, now: .now, calendar: calendar)
            && (language == nil || recordLanguage == nil || recordLanguage == language)
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty && recordings.isEmpty && baselines.isEmpty {
                    ContentUnavailableView {
                        Label("아직 기록이 없어요", systemImage: "calendar")
                    } description: {
                        Text("‘반복 루프 재생’으로 30초 넘게 연습하면 연습 기록이 저절로 남아요. 요약 카드의 ‘기록에 남기기’를 누르면 녹음도 여기에 모여요.")
                    }
                } else {
                    historyList
                }
            }
            .navigationTitle("기록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 기록이 없을 때도 알림은 켤 수 있게 목록 밖(위 막대)에 둔다.
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingReminder = true
                    } label: {
                        Label("연습 알림", systemImage: isReminderEnabled ? "bell.fill" : "bell")
                    }
                }
            }
            .sheet(isPresented: $isShowingReminder) {
                ReminderSettingsView(archive: audio.archive)
            }
            // 저장소 파일을 열지 못해 메모리에만 기록하는 중이면, 기록이 있든 없든 맨 위에 알린다.
            .safeAreaInset(edge: .top, spacing: 0) {
                if audio.archive.isTemporary {
                    temporaryStoreBanner
                }
            }
            .alert("지우지 못했어요", isPresented: $deleteFailed) {
                Button("확인", role: .cancel) {}
            } message: {
                Text("기록을 저장하지 못했어요. 저장 공간을 확인해 주세요. 기록은 그대로 있어요.")
            }
        }
        // 오늘 연습 기록을 지웠으면 오늘 알림을 다시 넣는다.
        .onChange(of: sessions.count) {
            PracticeReminder.refresh(using: audio.archive)
        }
    }

    private var historyList: some View {
        let points = PracticeHistory.filter(sessions.map { SessionPoint($0) }, period: period, language: language,
                                            now: .now, calendar: calendar)
        let shownRecordings = recordings.filter { isShown($0.recordedAt, $0.language) }
        let shownSessions = sessions.reversed().filter { isShown($0.startedAt, $0.language) }
        let shownBaselines = baselines.filter { isShown($0.measuredAt) }

        return List {
            Section {
                Picker("기간", selection: $period) {
                    ForEach(HistoryPeriod.allCases) { period in
                        Text(period.label).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                Picker("말한 언어", selection: $language) {
                    Text("모든 언어").tag(PracticeLanguage?.none)
                    ForEach(PracticeLanguage.allCases) { language in
                        Text(language.label).tag(PracticeLanguage?.some(language))
                    }
                }
            }

            Section {
                totalsRow(PracticeHistory.totals(points, calendar: calendar))
                if points.isEmpty {
                    Text("이 기간에 남은 연습 기록이 없어요.")
                        .foregroundStyle(.secondary)
                } else {
                    HistoryChartView(
                        points: points,
                        daily: PracticeHistory.dailyPractice(points, calendar: calendar),
                        dateDomain: PracticeHistory.dateDomain(points, period: period, now: .now, calendar: calendar),
                        pitchDomain: PracticeHistory.pitchDomain(points, target: target, baseline: baselineMedian),
                        target: target,
                        baseline: baselineMedian,
                        resonanceDomain: PracticeHistory.resonanceDomain(points, baseline: baselineF2),
                        baselineF2: baselineF2
                    )
                    .padding(.vertical, 6)
                }
            }

            Section {
                if shownRecordings.isEmpty {
                    Text("요약 카드의 ‘기록에 남기기’로 남긴 녹음이 여기에 모여요.")
                        .foregroundStyle(.secondary)
                }
                if recordings.count >= 2 {
                    Button {
                        // 지금 보이는 녹음(기간·언어)이 두 개 이상이면 그 안에서, 아니면 전체에서 처음과 최근을 고른다.
                        let candidates = shownRecordings.count >= 2 ? shownRecordings : recordings
                        if let pair = RecordingComparison.defaultPair(candidates, date: { $0.recordedAt }) {
                            comparePair = ComparePair(a: pair.a, b: pair.b)
                        }
                    } label: {
                        Label("두 녹음 나란히 비교", systemImage: "rectangle.split.2x1")
                    }
                }
                ForEach(shownRecordings) { recording in
                    NavigationLink {
                        RecordingDetailView(recording: recording, archive: audio.archive,
                                            canPlay: !audio.isRunning && !audio.isAnalyzingFile) {
                            onPlay(recording)
                        }
                    } label: {
                        recordingRow(recording)
                    }
                    .swipeActions {
                        Button("지우기", role: .destructive) {
                            delete { try audio.archive.delete(recording) }
                        }
                    }
                }
            } header: {
                Text("남긴 녹음")
            }

            if !shownSessions.isEmpty {
                Section {
                    ForEach(shownSessions) { session in
                        NavigationLink {
                            PracticeSessionDetailView(session: session)
                        } label: {
                            sessionRow(session)
                        }
                        .swipeActions {
                            Button("지우기", role: .destructive) {
                                delete { try audio.archive.delete(session) }
                            }
                        }
                    }
                } header: {
                    Text("연습 기록")
                } footer: {
                    Text("정지할 때마다 숫자만 저절로 남아요 (소리는 남지 않아요). 누르면 녹음마다의 숫자를 보고 AI에게 보낼 수 있어요. 밀어서 지울 수 있어요.")
                }
            }

            if !shownBaselines.isEmpty {
                Section("내 목소리 재기") {
                    ForEach(shownBaselines) { baseline in
                        baselineRow(baseline)
                            .swipeActions {
                                Button("지우기", role: .destructive) {
                                    delete { try audio.archive.delete(baseline) }
                                }
                            }
                    }
                }
            }

            Section {
                Button("모든 기록 지우기", role: .destructive) {
                    isConfirmingDeleteAll = true
                }
            } footer: {
                Text("기록은 이 기기 안에만 있어요. 남긴 녹음의 소리는 iCloud 백업에도 들어가지 않아서, 기기를 바꾸면 옮겨지지 않아요.")
            }
        }
        .sheet(item: $comparePair) { pair in
            RecordingCompareView(recordings: recordings, initialA: pair.a, initialB: pair.b,
                                 archive: audio.archive, audio: audio)
        }
        .confirmationDialog("모든 기록을 지울까요?", isPresented: $isConfirmingDeleteAll, titleVisibility: .visible) {
            Button("모두 지우기", role: .destructive) {
                delete { try audio.archive.deleteAll() }
            }
        } message: {
            Text("연습 기록, 남긴 녹음과 메모, 내 목소리·모음 재기 이력이 모두 지워져요. 지금 쓰는 기준 목소리·목표 범위·모음 지도는 그대로예요. 되돌릴 수 없어요.")
        }
    }

    /// 지우기를 하고, 실패하면 안내한다.
    private func delete(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            deleteFailed = true
        }
    }

    private var temporaryStoreBanner: some View {
        Label("이번 실행 동안만 기록이 유지돼요. 앱을 다시 켜면 이번에 남긴 기록은 사라져요.",
              systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.18))
    }

    // MARK: - 줄

    private func totalsRow(_ totals: PracticeHistory.Totals) -> some View {
        HStack(spacing: 0) {
            stat("연습", "\(totals.sessionCount)번")
            stat("연습한 날", "\(totals.dayCount)일")
            stat("모두", PracticeHistory.totalLabel(totals.practiceSeconds))
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recordingRow(_ recording: SavedRecording) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(recording.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(PitchSummary.durationLabel(recording.durationSeconds))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("중앙 \(Int(recording.medianHz.rounded())) Hz · \(Int(recording.lowHz.rounded()))–\(Int(recording.highHz.rounded())) Hz")
                    .font(.footnote)
                    .monospacedDigit()
                Spacer()
                languageTag(recording.language)
            }
            if !recording.memo.isEmpty {
                Text(recording.memo)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func sessionRow(_ session: PracticeSession) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.startedAt.formatted(.dateTime.month().day().weekday().hour().minute()))
                    .font(.subheadline)
                Text("연습 \(PracticeHistory.totalLabel(session.practiceSeconds)) · 녹음 \(session.takeCount)번")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("중앙 \(Int(session.medianHz.rounded())) Hz")
                    .font(.subheadline)
                    .monospacedDigit()
                languageTag(session.language)
            }
        }
    }

    private func baselineRow(_ baseline: BaselineRecord) -> some View {
        HStack {
            Text(baseline.measuredAt.formatted(.dateTime.month().day().weekday()))
                .font(.subheadline)
            Spacer()
            Text("중앙 \(Int(baseline.medianHz.rounded())) Hz · \(Int(baseline.lowHz.rounded()))–\(Int(baseline.highHz.rounded())) Hz")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(UllimColor.reference)
        }
    }

    /// 언어 표시: 그래프 점과 같은 모양(분홍) + 언어 이름
    private func languageTag(_ language: PracticeLanguage) -> some View {
        HStack(spacing: 3) {
            Image(systemName: language.symbolName)
                .font(.system(size: 7))
                .foregroundStyle(UllimColor.voice)
            Text(language.label)
                .foregroundStyle(.secondary)
        }
        .font(.caption2.weight(.medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color(.tertiarySystemFill), in: Capsule())
    }
}
