import SwiftUI
import UIKit

/// 연습 알림 설정: 켜기·끄기와 시간. 기본은 꺼짐이고, 켤 때만 알림 권한을 묻는다.
struct ReminderSettingsView: View {
    let archive: PracticeArchive

    @AppStorage(PracticeReminder.enabledKey) private var isEnabled = false
    @AppStorage(PracticeReminder.minuteOfDayKey) private var minuteOfDay = PracticeReminder.defaultMinuteOfDay
    /// iPhone 설정에서 이 앱의 알림이 꺼져 있는지
    @State private var isDenied = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var enabledBinding: Binding<Bool> {
        Binding(get: { isEnabled }, set: { newValue in
            Task { await setEnabled(newValue) }
        })
    }

    private var timeBinding: Binding<Date> {
        Binding(get: { PracticeReminder.date(forMinuteOfDay: minuteOfDay) },
                set: { minuteOfDay = PracticeReminder.minuteOfDay(of: $0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("매일 연습 알림", isOn: enabledBinding)
                    if isEnabled {
                        DatePicker("알림 시간", selection: timeBinding, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("정한 시간에 하루 한 번 “\(PracticeReminder.body)”라고 알려 줘요. 그날 이미 연습 기록이 남았으면 알리지 않아요.")
                }

                if isDenied {
                    Section {
                        Label("iPhone 설정에서 ‘울림’의 알림이 꺼져 있어요.", systemImage: "bell.slash")
                            .foregroundStyle(.orange)
                        Button("설정에서 알림 켜기") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                }

                Section {
                    Text("목이 아프거나 쉰 날에는 알림이 와도 쉬어 가세요. 연습을 쉬어도 기록에 표시되는 것은 없어요.")
                    Text("알림은 이 기기 안에서 예약해요. 울림을 14일 넘게 열지 않으면 알림도 멈추고, 다시 열면 이어서 알려 줘요.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("연습 알림")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            // 설정 앱에서 알림을 끄고 돌아왔을 수도 있으니 열 때마다 확인한다.
            let permission = await PracticeReminder.permission()
            isDenied = isEnabled && permission == .denied
        }
        .onChange(of: minuteOfDay) {
            PracticeReminder.refresh(using: archive)
        }
    }

    private func setEnabled(_ on: Bool) async {
        if on {
            guard await PracticeReminder.requestPermission() else {
                isDenied = true
                isEnabled = false
                return
            }
        }
        isDenied = false
        isEnabled = on
        PracticeReminder.refresh(using: archive)
    }
}
