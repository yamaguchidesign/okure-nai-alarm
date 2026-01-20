//
//  okure_naiApp.swift
//  okure-nai
//
//  Created by 山口翔平 on 2025/10/12.
//

import AppKit
import Combine
import SwiftUI
import UserNotifications

// アラームデータモデル
struct Alarm: Identifiable, Codable {
    let id: UUID
    var hour: Int
    var minute: Int
    var isEnabled: Bool = true
    var isCalendarAlarm: Bool = false  // カレンダー連携で自動生成されたアラームかどうか
    var calendarEventTitle: String? = nil // カレンダー予定のタイトル（表示用）

    init(hour: Int, minute: Int, isEnabled: Bool = true, isCalendarAlarm: Bool = false, calendarEventTitle: String? = nil) {
        self.id = UUID()
        self.hour = hour
        self.minute = minute
        self.isEnabled = isEnabled
        self.isCalendarAlarm = isCalendarAlarm
        self.calendarEventTitle = calendarEventTitle
    }

    var timeString: String {
        return String(format: "%02d:%02d", hour, minute)
    }

    var date: Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    // 繰り返し設定機能は廃止（常に一回限り）
}

// アラーム管理クラス
class AlarmStore: ObservableObject {
    @Published var alarms: [Alarm] = []

    private let userDefaults = UserDefaults.standard
    private let alarmsKey = "SavedAlarms"

    init() {
        loadAlarms()
    }

    func addAlarm(_ alarm: Alarm) {
        alarms.append(alarm)
        saveAlarms()
    }

    func updateAlarm(_ alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
            saveAlarms()
        }
    }

    func deleteAlarm(at indexSet: IndexSet) {
        alarms.remove(atOffsets: indexSet)
        saveAlarms()
    }

    func deleteAlarm(_ alarm: Alarm) {
        alarms.removeAll { $0.id == alarm.id }
        saveAlarms()
    }

    func toggleAlarm(_ alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index].isEnabled.toggle()
            saveAlarms()
        }
    }

    func disableAlarm(_ alarm: Alarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index].isEnabled = false
            saveAlarms()
        }
    }

    private func saveAlarms() {
        if let encoded = try? JSONEncoder().encode(alarms) {
            userDefaults.set(encoded, forKey: alarmsKey)
        }
    }

    private func loadAlarms() {
        if let data = userDefaults.data(forKey: alarmsKey),
            let decoded = try? JSONDecoder().decode([Alarm].self, from: data)
        {
            alarms = decoded
        }
    }

    func getEnabledAlarms() -> [Alarm] {
        return alarms.filter { $0.isEnabled }
    }
    
    // カレンダーアラームを削除
    func removeCalendarAlarms() {
        alarms.removeAll { $0.isCalendarAlarm }
        saveAlarms()
    }
    
    // カレンダーアラームを追加
    func addCalendarAlarm(_ alarm: Alarm) {
        alarms.append(alarm)
        saveAlarms()
    }
}

@main
struct okure_naiApp: App {
    @StateObject private var alarmManager = AlarmManager()
    @StateObject private var menuBarManager = MenuBarManager()
    @StateObject private var calendarService = GoogleCalendarService()
    @StateObject private var alarmStore = AlarmStore()
    @StateObject private var calendarScheduler: CalendarAlarmScheduler
    
    init() {
        let alarmStore = AlarmStore()
        let calendarService = GoogleCalendarService()
        let scheduler = CalendarAlarmScheduler(calendarService: calendarService, alarmStore: alarmStore)
        _calendarScheduler = StateObject(wrappedValue: scheduler)
        _alarmStore = StateObject(wrappedValue: alarmStore)
        _calendarService = StateObject(wrappedValue: calendarService)
        
        // OAuthコールバックを処理
        URLHandler.shared.setup()
        URLHandler.shared.calendarService = calendarService
        URLHandler.shared.calendarScheduler = scheduler
    }

    var body: some Scene {
        // メニューバーアプリ
        MenuBarExtra("アラーム", systemImage: "alarm") {
            MenuBarView()
                .environmentObject(alarmManager)
                .environmentObject(menuBarManager)
                .environmentObject(calendarService)
                .environmentObject(calendarScheduler)
                .environmentObject(alarmStore)
                .onAppear {
                    // メニューバーウィンドウの動作を調整
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.configureMenuBarWindow()
                    }
                }
        }
        .menuBarExtraStyle(.window)

        // アラーム表示用のウィンドウ
        Window("アラーム", id: "alarm-panel") {
            if let alarmTime = alarmManager.alarmTime {
                AlarmPanelWindow(alarmTime: alarmTime) {
                    alarmManager.stopAlarm()
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
    }

    private func configureMenuBarWindow() {
        // メニューバーウィンドウを探して設定
        for window in NSApp.windows {
            if window.identifier?.rawValue == "MenuBarExtra" {
                window.level = .floating
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                window.isReleasedWhenClosed = false

                // 外側クリックで閉じないようにする
                if let windowDelegate = window.delegate {
                    // ウィンドウのデリゲートを設定
                } else {
                    window.delegate = MenuBarWindowDelegate()
                }
                break
            }
        }
    }
}

// メニューバーウィンドウ用デリゲート
class MenuBarWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 外側クリックでも閉じない
        return false
    }

    func windowWillClose(_ notification: Notification) {
        // ウィンドウが閉じようとするのを防ぐ
    }
}

// アラーム管理用のObservableObject
class AlarmManager: ObservableObject {
    @Published var showAlarmPanel = false
    @Published var alarmTime: Date?

    private var alarmWindow: NSWindow?
    private var lastTriggeredStamp: String?
    private var onStop: (() -> Void)?

    func triggerAlarm(time: Date) {
        // 同じ「分」での再発火を防ぐ（停止ボタンを押してもすぐ再表示される問題の対策）
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: time)
        let stamp = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0) \(c.hour ?? 0):\(c.minute ?? 0)"
        if lastTriggeredStamp == stamp {
            return
        }
        lastTriggeredStamp = stamp

        alarmTime = time
        showAlarmPanel = true

        // アプリをアクティブ化して最前面に
        NSApp.activate(ignoringOtherApps: true)

        // アラームパネルウィンドウを開く
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.openAlarmWindow()
        }
    }

    func dismissAlarm() {
        DispatchQueue.main.async {
            self.showAlarmPanel = false
            self.alarmTime = nil
            self.closeAlarmWindow()
        }
    }

    func setOnStop(_ handler: (() -> Void)?) {
        self.onStop = handler
    }

    func stopAlarm() {
        onStop?()
        onStop = nil
        dismissAlarm()
    }

    private func openAlarmWindow() {
        // 既存のウィンドウがあれば閉じる
        closeAlarmWindow()

        // 新規ウィンドウを開く
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = "アラーム"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        window.isReleasedWhenClosed = false

        // アラームパネルを表示
        if let alarmTime = self.alarmTime {
            let hostingView = NSHostingView(
                rootView: AlarmPanelWindow(alarmTime: alarmTime) {
                    self.stopAlarm()
                }
            )
            window.contentView = hostingView
        }

        // ウィンドウを表示
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // ウィンドウを保持
        self.alarmWindow = window
    }

    private func closeAlarmWindow() {
        if let window = alarmWindow {
            window.close()
            alarmWindow = nil
        }
    }
}

struct AlarmPanelWindow: View {
    let alarmTime: Date
    let onStop: () -> Void

    @State private var scale: CGFloat = 0.5
    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // 背景
            Color.black.opacity(0.95)
                .ignoresSafeArea()

            VStack(spacing: 40) {
                // アラームアイコン
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 200, height: 200)
                        .scaleEffect(pulseScale)

                    Image(systemName: "alarm.fill")
                        .resizable()
                        .frame(width: 100, height: 100)
                        .foregroundColor(.red)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                        pulseScale = 1.2
                    }
                }

                VStack(spacing: 20) {
                    Text(alarmTime, style: .time)
                        .font(.system(size: 96, weight: .bold))
                        .foregroundColor(.red)

                    Text("設定した時刻になりました")
                        .font(.title)
                        .foregroundColor(.white.opacity(0.8))
                }

                Button(action: onStop) {
                    Text("停止")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 200, height: 70)
                        .background(Color.red)
                        .cornerRadius(35)
                        .shadow(color: .red.opacity(0.5), radius: 20, x: 0, y: 10)
                }
                .buttonStyle(.plain)
            }
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    scale = 1.0
                }

                // サウンドを鳴らす
                NSSound.beep()
            }
        }
        .frame(width: 800, height: 600)
    }
}

// メニューバー管理クラス
class MenuBarManager: ObservableObject {
    // 将来的にメニューバー固有の機能を追加する際に使用
}

// メニューバー表示ビュー
struct MenuBarView: View {
    @EnvironmentObject var alarmManager: AlarmManager
    @EnvironmentObject var menuBarManager: MenuBarManager
    @EnvironmentObject var calendarService: GoogleCalendarService
    @EnvironmentObject var calendarScheduler: CalendarAlarmScheduler
    @EnvironmentObject var alarmStore: AlarmStore
    @State private var showingAddAlarm = false
    @State private var selectedHour = 9
    @State private var selectedMinute = 0
    @State private var showingCalendarSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack {
                Text("Okure-nai アラーム")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // 注釈テキスト
            Text("指定時刻の2分前に通知します")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            Divider()
            
            // Googleカレンダー連携セクション
            if showingCalendarSettings {
                CalendarSettingsView(
                    calendarService: calendarService,
                    calendarScheduler: calendarScheduler,
                    onDismiss: { showingCalendarSettings = false }
                )
            } else {
                // カレンダー連携ステータス
                CalendarStatusView(
                    calendarService: calendarService,
                    calendarScheduler: calendarScheduler,
                    onShowSettings: { showingCalendarSettings = true }
                )
            }

            Divider()

            // アラーム追加画面または一覧表示
            if showingAddAlarm {
                MenuBarAddAlarmView(
                    alarmStore: alarmStore, selectedHour: $selectedHour,
                    selectedMinute: $selectedMinute, showingAddAlarm: $showingAddAlarm)
            } else if alarmStore.alarms.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "alarm")
                        .font(.title2)
                        .foregroundColor(.gray)

                    Text("アラームがありません")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(alarmStore.alarms) { alarm in
                            MenuBarAlarmRow(alarm: alarm, alarmStore: alarmStore)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(maxHeight: 200)
            }

            Divider()

            // ボタン（アラーム追加画面でない場合のみ表示）
            if !showingAddAlarm {
                VStack(spacing: 0) {
                    Button(action: { showingAddAlarm = true }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("アラーム追加")
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color.blue)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .frame(width: showingAddAlarm || showingCalendarSettings ? 320 : 280)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            checkAlarms()

            // メニューバーウィンドウの設定を定期的に確認
            DispatchQueue.main.async {
                self.ensureMenuBarWindowConfigured()
            }
        }
        .background(Color.clear)
        .onTapGesture {
            // パネル内をクリックしても閉じないようにする
        }
    }

    private func checkAlarms() {
        let enabledAlarms = alarmStore.getEnabledAlarms()
        guard !alarmManager.showAlarmPanel else { return }

        let calendar = Calendar.current
        let currentComponents = calendar.dateComponents([.hour, .minute], from: Date())

        for alarm in enabledAlarms {
            // 時刻のチェック
            guard currentComponents.hour == alarm.hour && currentComponents.minute == alarm.minute
            else { continue }

            triggerAlarm(alarm)
            break
        }
    }

    private func triggerAlarm(_ alarm: Alarm) {
        // 「停止」されたら、このアラーム自体を無効化して再表示/再発火を防ぐ
        alarmManager.setOnStop {
            alarmStore.disableAlarm(alarm)
        }
        alarmManager.triggerAlarm(time: alarm.date)
        sendNotification()
    }

    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "アラーム"
        content.body = "設定した時刻になりました！"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func ensureMenuBarWindowConfigured() {
        // メニューバーウィンドウが正しく設定されているか確認
        for window in NSApp.windows {
            if window.identifier?.rawValue == "MenuBarExtra" {
                if window.delegate == nil {
                    window.delegate = MenuBarWindowDelegate()
                }
                break
            }
        }
    }

}

// メニューバー用アラーム行
struct MenuBarAlarmRow: View {
    let alarm: Alarm
    let alarmStore: AlarmStore

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(alarm.timeString)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(alarm.isEnabled ? .primary : .secondary)
                    
                    if alarm.isCalendarAlarm {
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }

                Text(alarm.isCalendarAlarm ? (alarm.calendarEventTitle ?? "カレンダー予定") : "一回限り")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Toggle(
                    isOn: Binding(
                        get: { alarm.isEnabled },
                        set: { _ in alarmStore.toggleAlarm(alarm) }
                    )
                ) {
                    Text("")
                }
                .toggleStyle(SwitchToggleStyle())
                .scaleEffect(0.8)

                // カレンダーアラームは削除ボタンを表示しない（自動管理のため）
                if !alarm.isCalendarAlarm {
                    Button(action: {
                        alarmStore.deleteAlarm(alarm)
                    }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// メニューバー用アラーム追加ビュー
struct MenuBarAddAlarmView: View {
    let alarmStore: AlarmStore
    @Binding var selectedHour: Int
    @Binding var selectedMinute: Int
    @Binding var showingAddAlarm: Bool

    @State private var hoveredHour: Int? = nil
    @State private var hideTimer: Timer? = nil

    var body: some View {
        VStack(spacing: 20) {
            // 時刻選択ボタン
            VStack(alignment: .leading, spacing: 8) {
                Text("時刻選択")
                    .font(.subheadline)
                    .fontWeight(.medium)

                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                        spacing: 8
                    ) {
                        ForEach(9...20, id: \.self) { hour in
                            VStack(spacing: 4) {
                                // メインの時間ボタン（:00）
                                Button(action: {
                                    selectedHour = hour
                                    selectedMinute = 0
                                }) {
                                    Text(String(format: "%d:00", hour))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(
                                            isTimeSelected(hour: hour, minute: 0)
                                                ? .white : .primary
                                        )
                                        .frame(width: 70, height: 32)
                                        .background(
                                            isTimeSelected(hour: hour, minute: 0)
                                                ? Color.blue : Color.gray.opacity(0.2)
                                        )
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .onHover { isHovering in
                                    if isHovering {
                                        // ホバー時は即座に表示
                                        hideTimer?.invalidate()
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            hoveredHour = hour
                                        }
                                    } else {
                                        // ホバー解除時は少し遅延してから非表示
                                        hideTimer?.invalidate()
                                        hideTimer = Timer.scheduledTimer(
                                            withTimeInterval: 0.3, repeats: false
                                        ) { _ in
                                            withAnimation(.easeInOut(duration: 0.2)) {
                                                hoveredHour = nil
                                            }
                                        }
                                    }
                                }

                                // ホバー時の:30オプション（固定高さで予約）
                                ZStack {
                                    // 透明なプレースホルダーで高さを確保
                                    Color.clear
                                        .frame(width: 70, height: 24)

                                    // 実際の30分ボタン（ホバー時または30分が選択されている時）
                                    if hoveredHour == hour
                                        || (selectedHour == hour && selectedMinute == 30)
                                    {
                                        Button(action: {
                                            selectedHour = hour
                                            selectedMinute = 30
                                        }) {
                                            Text(String(format: "%d:30", hour))
                                                .font(.caption)
                                                .fontWeight(.medium)
                                                .foregroundColor(
                                                    isTimeSelected(hour: hour, minute: 30)
                                                        ? .white : .primary
                                                )
                                                .frame(width: 70, height: 24)
                                                .background(
                                                    isTimeSelected(hour: hour, minute: 30)
                                                        ? Color.blue : Color.gray.opacity(0.3)
                                                )
                                                .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                                        .onHover { isHovering in
                                            if isHovering {
                                                // 30分ボタンにホバー中はタイマーを無効化
                                                hideTimer?.invalidate()
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(height: 60)  // 固定高さを設定
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .frame(height: 280)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.horizontal, 20)

            // 現在の設定時刻表示
            Text("設定時刻: \(String(format: "%02d:%02d", selectedHour, selectedMinute))")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            // ボタン
            HStack(spacing: 12) {
                Button("キャンセル") {
                    showingAddAlarm = false
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Color.gray.opacity(0.2))
                .foregroundColor(.primary)
                .cornerRadius(6)
                .buttonStyle(.plain)

                Button("保存") {
                    var newAlarm = Alarm(hour: selectedHour, minute: selectedMinute)
                    alarmStore.addAlarm(newAlarm)
                    showingAddAlarm = false
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(6)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private func isTimeSelected(hour: Int, minute: Int) -> Bool {
        return selectedHour == hour && selectedMinute == minute
    }
}

// カレンダー連携ステータスビュー
struct CalendarStatusView: View {
    @ObservedObject var calendarService: GoogleCalendarService
    @ObservedObject var calendarScheduler: CalendarAlarmScheduler
    let onShowSettings: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: calendarService.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(calendarService.isAuthenticated ? .green : .gray)
                
                Text("Googleカレンダー")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            
            if calendarService.isAuthenticated {
                if calendarScheduler.isEnabled {
                    HStack {
                        Text("連携中")
                            .font(.caption)
                            .foregroundColor(.green)
                        
                        Spacer()
                        
                        if let lastSync = calendarScheduler.lastSyncDate {
                            Text("最終同期: \(formatDate(lastSync))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                } else {
                    Text("連携が無効です")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                }
            } else {
                Text("未認証")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            }
            
            HStack(spacing: 8) {
                Button("今すぐ同期") {
                    Task {
                        await calendarScheduler.syncTodayAlarms()
                    }
                }
                .font(.caption)
                .frame(maxWidth: .infinity)
                .frame(height: 24)
                .buttonStyle(.bordered)
                .disabled(!(calendarService.isAuthenticated && calendarScheduler.isEnabled))
                
                Button(action: onShowSettings) {
                    HStack {
                        Image(systemName: "gear")
                        Text("設定")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// カレンダー設定ビュー
struct CalendarSettingsView: View {
    @ObservedObject var calendarService: GoogleCalendarService
    @ObservedObject var calendarScheduler: CalendarAlarmScheduler
    let onDismiss: () -> Void
    @State private var clientId: String = ""
    @State private var clientSecret: String = ""
    @State private var showingOAuth = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                
                Text("Googleカレンダー設定")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 認証情報入力
                    VStack(alignment: .leading, spacing: 8) {
                        Text("認証情報")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Text("Google Cloud Consoleで取得したClient IDとClient Secretを入力してください")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        TextField("Client ID", text: $clientId)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        
                        SecureField("Client Secret", text: $clientSecret)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                        
                        Button("認証情報を保存") {
                            calendarService.setCredentials(clientId: clientId, clientSecret: clientSecret)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    
                    Divider()
                    
                    // 認証状態
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("認証状態")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            if calendarService.isAuthenticated {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                    Text("認証済み")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            } else {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                    Text("未認証")
                                        .font(.caption2)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        if !calendarService.isAuthenticated {
                            Button("Googleで認証") {
                                if let url = calendarService.getAuthorizationURL() {
                                    NSWorkspace.shared.open(url)
                                } else {
                                    // Client IDが設定されていない場合のエラーメッセージ
                                    let alert = NSAlert()
                                    alert.messageText = "認証情報が設定されていません"
                                    alert.informativeText = "Client IDとClient Secretを設定画面で入力してください。"
                                    alert.alertStyle = .warning
                                    alert.addButton(withTitle: "OK")
                                    alert.runModal()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        } else {
                            Button("ログアウト") {
                                calendarService.logout()
                                calendarScheduler.disable()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    Divider()
                    
                    // 連携設定
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("自動アラーム設定")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { calendarScheduler.isEnabled },
                                set: { enabled in
                                    if enabled {
                                        calendarScheduler.enable()
                                    } else {
                                        calendarScheduler.disable()
                                    }
                                }
                            ))
                            .toggleStyle(SwitchToggleStyle())
                            .scaleEffect(0.8)
                        }
                        
                        Text("毎日00:00にその日の予定を取得し、開始時刻の2分前にアラームを自動設定します")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("ゲストがいる予定のみアラームを有効にする")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { calendarScheduler.onlyEventsWithGuests },
                                set: { value in
                                    calendarScheduler.onlyEventsWithGuests = value
                                }
                            ))
                            .toggleStyle(SwitchToggleStyle())
                            .scaleEffect(0.8)
                        }
                        .disabled(!calendarService.isAuthenticated)
                        
                        if let lastSync = calendarScheduler.lastSyncDate {
                            Text("最終同期: \(formatDateTime(lastSync))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if let nextCheck = calendarScheduler.nextCheckDate {
                            Text("次回チェック: \(formatDateTime(nextCheck))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Button("今すぐ同期") {
                            Task {
                                await calendarScheduler.syncTodayAlarms()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!calendarService.isAuthenticated)
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 8)
            }
        }
        .frame(height: 400)
        .onAppear {
            // 保存済みの認証情報を読み込む
            clientId = UserDefaults.standard.string(forKey: "GoogleCalendarClientId") ?? ""
            clientSecret = UserDefaults.standard.string(forKey: "GoogleCalendarClientSecret") ?? ""
        }
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
