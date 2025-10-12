//
//  okure_naiApp.swift
//  okure-nai
//
//  Created by 山口翔平 on 2025/10/12.
//

import SwiftUI
import Combine
import AppKit

@main
struct okure_naiApp: App {
    @StateObject private var alarmManager = AlarmManager()
    @StateObject private var menuBarManager = MenuBarManager()
    
    var body: some Scene {
        // メニューバーアプリ
        MenuBarExtra("アラーム", systemImage: "alarm") {
            MenuBarView()
                .environmentObject(alarmManager)
                .environmentObject(menuBarManager)
        }
        .menuBarExtraStyle(.window)
        
        // アラーム表示用のウィンドウ
        Window("アラーム", id: "alarm-panel") {
            if let alarmTime = alarmManager.alarmTime {
                AlarmPanelWindow(alarmTime: alarmTime) {
                    alarmManager.dismissAlarm()
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
    }
}

// アラーム管理用のObservableObject
class AlarmManager: ObservableObject {
    @Published var showAlarmPanel = false
    @Published var alarmTime: Date?
    
    private var alarmWindow: NSWindow?
    
    func triggerAlarm(time: Date) {
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
            let hostingView = NSHostingView(rootView: AlarmPanelWindow(alarmTime: alarmTime) {
                self.dismissAlarm()
            })
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
    let onDismiss: () -> Void
    
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
                
                Button(action: onDismiss) {
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
    @Published var showMainWindow = false
    
    func toggleMainWindow() {
        showMainWindow.toggle()
    }
}

// メニューバー表示ビュー
struct MenuBarView: View {
    @EnvironmentObject var alarmManager: AlarmManager
    @EnvironmentObject var menuBarManager: MenuBarManager
    @StateObject private var alarmStore = AlarmStore()
    @State private var currentTime = Date()
    @State private var showingAddAlarm = false
    @State private var selectedHour = Calendar.current.component(.hour, from: Date())
    @State private var selectedMinute = Calendar.current.component(.minute, from: Date())
    @State private var timeInput = ""
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack {
                Text("アラーム")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            Divider()
            
            // 現在時刻
            HStack {
                Text("現在時刻:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(currentTime, style: .time)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            
            Divider()
            
            // アラーム一覧
            if alarmStore.alarms.isEmpty {
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
            
            // ボタン
            VStack(spacing: 8) {
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
                
                Button(action: { menuBarManager.toggleMainWindow() }) {
                    HStack {
                        Image(systemName: "gear")
                        Text("設定")
                    }
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 280)
        .onReceive(timer) { _ in
            currentTime = Date()
            checkAlarms()
        }
        .sheet(isPresented: $showingAddAlarm) {
            MenuBarAddAlarmView(alarmStore: alarmStore, selectedHour: $selectedHour, selectedMinute: $selectedMinute, timeInput: $timeInput)
        }
        .sheet(isPresented: $menuBarManager.showMainWindow) {
            ContentView()
                .environmentObject(alarmManager)
        }
    }
    
    private func checkAlarms() {
        let enabledAlarms = alarmStore.getEnabledAlarms()
        guard !alarmManager.showAlarmPanel else { return }
        
        let calendar = Calendar.current
        let currentComponents = calendar.dateComponents([.hour, .minute], from: currentTime)
        
        for alarm in enabledAlarms {
            if currentComponents.hour == alarm.hour &&
               currentComponents.minute == alarm.minute {
                triggerAlarm(alarm)
                break
            }
        }
    }
    
    private func triggerAlarm(_ alarm: Alarm) {
        alarmManager.triggerAlarm(time: alarm.date)
        sendNotification()
    }
    
    private func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "アラーム"
        content.body = "設定した時刻になりました！"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// メニューバー用アラーム行
struct MenuBarAlarmRow: View {
    let alarm: Alarm
    let alarmStore: AlarmStore
    
    var body: some View {
        HStack {
            Text(alarm.timeString)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(alarm.isEnabled ? .primary : .secondary)
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { _ in alarmStore.toggleAlarm(alarm) }
            ))
            .toggleStyle(SwitchToggleStyle())
            .scaleEffect(0.8)
        }
        .padding(.vertical, 4)
    }
}

// メニューバー用アラーム追加ビュー
struct MenuBarAddAlarmView: View {
    let alarmStore: AlarmStore
    @Binding var selectedHour: Int
    @Binding var selectedMinute: Int
    @Binding var timeInput: String
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("アラーム追加")
                .font(.headline)
                .padding(.top, 20)
            
            // 時刻直接入力
            VStack(alignment: .leading, spacing: 8) {
                Text("時刻入力（例：2345 → 23:45）")
                    .font(.subheadline)
                
                TextField("2345", text: $timeInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: timeInput) { newValue in
                        parseTimeInput(newValue)
                    }
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
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(6)
                
                Button("保存") {
                    let newAlarm = Alarm(hour: selectedHour, minute: selectedMinute)
                    alarmStore.addAlarm(newAlarm)
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(width: 300, height: 250)
    }
    
    private func parseTimeInput(_ input: String) {
        let numbers = input.filter { $0.isNumber }
        
        if numbers.count >= 3 {
            let hourString = String(numbers.prefix(numbers.count - 2))
            let minuteString = String(numbers.suffix(2))
            
            if let hour = Int(hourString), let minute = Int(minuteString) {
                if hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 {
                    selectedHour = hour
                    selectedMinute = minute
                }
            }
        } else if numbers.count == 2 {
            if let minute = Int(numbers) {
                if minute >= 0 && minute <= 59 {
                    selectedMinute = minute
                }
            }
        } else if numbers.count == 1 {
            if let minute = Int(numbers) {
                selectedMinute = (selectedMinute / 10) * 10 + minute
                if selectedMinute > 59 {
                    selectedMinute = minute
                }
            }
        }
    }
}
