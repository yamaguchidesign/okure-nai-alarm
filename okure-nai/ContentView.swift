//
//  ContentView.swift
//  okure-nai
//
//  Created by 山口翔平 on 2025/10/12.
//

import SwiftUI
import Combine
import UserNotifications

struct ContentView: View {
    @EnvironmentObject var alarmManager: AlarmManager
    @StateObject private var alarmStore = AlarmStore()
    @State private var selectedHour = Calendar.current.component(.hour, from: Date())
    @State private var selectedMinute = Calendar.current.component(.minute, from: Date())
    @State private var currentTime = Date()
    @State private var showingAddAlarm = false
    @State private var timeInput = ""
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // 現在時刻表示
                Text("現在時刻: \(currentTime, style: .time)")
                    .font(.title2)
                    .foregroundColor(.secondary)
                    .padding(.top, 20)
                
                // 説明テキスト
                Text("指定した時刻の2分前にアラートします")
                    .font(.subheadline)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 20)
                
                // アラーム一覧
                if alarmStore.alarms.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "alarm")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("アラームが設定されていません")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                Button(action: { showingAddAlarm = true }) {
                    Text("アラームを追加")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 200, height: 50)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(alarmStore.alarms) { alarm in
                            AlarmRowView(alarm: alarm, alarmStore: alarmStore)
                        }
                        .onDelete(perform: alarmStore.deleteAlarm)
                    }
                    .listStyle(PlainListStyle())
                }
                
                Spacer()
                
                // アラーム追加ボタン
                Button(action: { showingAddAlarm = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("アラームを追加")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("アラーム")
        }
        .sheet(isPresented: $showingAddAlarm) {
            AddAlarmView(alarmStore: alarmStore, selectedHour: $selectedHour, selectedMinute: $selectedMinute, timeInput: $timeInput)
        }
        .onReceive(timer) { _ in
            currentTime = Date()
            checkAlarms()
        }
    }
    
    func checkAlarms() {
        let enabledAlarms = alarmStore.getEnabledAlarms()
        guard !alarmManager.showAlarmPanel else { return }
        
        let calendar = Calendar.current
        let currentComponents = calendar.dateComponents([.hour, .minute], from: currentTime)
        
        for alarm in enabledAlarms {
            // 設定時刻から2分引いた時刻を計算
            var alarmComponents = DateComponents()
            alarmComponents.hour = alarm.hour
            alarmComponents.minute = alarm.minute
            
            if let alarmDate = calendar.date(from: alarmComponents),
               let twoMinutesBefore = calendar.date(byAdding: .minute, value: -2, to: alarmDate) {
                let targetComponents = calendar.dateComponents([.hour, .minute], from: twoMinutesBefore)
                
                // 2分前の時刻と現在時刻が一致したらアラーム発動
                if currentComponents.hour == targetComponents.hour &&
                   currentComponents.minute == targetComponents.minute {
                    triggerAlarm(alarm)
                    break // 一度に一つのアラームのみ発動
                }
            }
        }
    }
    
    func triggerAlarm(_ alarm: Alarm) {
        // アラームマネージャーを通じてアラームを発動
        alarmManager.triggerAlarm(time: alarm.date)
        
        // 通知を送信
        sendNotification()
    }
    
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("通知権限が許可されました")
            }
        }
    }
    
    func sendNotification() {
        let content = UNMutableNotificationContent()
        content.title = "アラーム"
        content.body = "設定した時刻になりました！"
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// アラーム行表示ビュー
struct AlarmRowView: View {
    let alarm: Alarm
    let alarmStore: AlarmStore
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.timeString)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(alarm.isEnabled ? .primary : .secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { _ in alarmStore.toggleAlarm(alarm) }
            ))
            .toggleStyle(SwitchToggleStyle())
        }
        .padding(.vertical, 8)
    }
}

// アラーム追加ビュー
struct AddAlarmView: View {
    let alarmStore: AlarmStore
    @Binding var selectedHour: Int
    @Binding var selectedMinute: Int
    @Binding var timeInput: String
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Text("アラーム時刻を設定")
                    .font(.headline)
                    .padding(.top, 20)
                
                HStack(spacing: 10) {
                    // 時
                    VStack(spacing: 8) {
                        Text(String(format: "%02d", selectedHour))
                            .font(.system(size: 72, weight: .bold))
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 10) {
                            Button(action: {
                                selectedHour = (selectedHour - 1 + 24) % 24
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                selectedHour = (selectedHour + 1) % 24
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Text("時")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 150)
                    
                    Text(":")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 30)
                    
                    // 分
                    VStack(spacing: 8) {
                        Text(String(format: "%02d", selectedMinute))
                            .font(.system(size: 72, weight: .bold))
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 10) {
                            Button(action: {
                                selectedMinute = (selectedMinute - 1 + 60) % 60
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                selectedMinute = (selectedMinute + 1) % 60
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title)
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Text("分")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 150)
                }
                .padding(30)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(15)
                
                // 時刻直接入力
                VStack(alignment: .leading, spacing: 8) {
                    Text("時刻直接入力（例：2345 → 23:45）")
                        .font(.headline)
                    
                    TextField("2345", text: $timeInput)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onChange(of: timeInput) { newValue in
                            parseTimeInput(newValue)
                        }
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .navigationTitle("アラーム追加")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let newAlarm = Alarm(hour: selectedHour, minute: selectedMinute)
                        alarmStore.addAlarm(newAlarm)
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func parseTimeInput(_ input: String) {
        // 数字のみを抽出
        let numbers = input.filter { $0.isNumber }
        
        if numbers.count >= 3 {
            let hourString = String(numbers.prefix(numbers.count - 2))
            let minuteString = String(numbers.suffix(2))
            
            if let hour = Int(hourString), let minute = Int(minuteString) {
                // 時間の範囲チェック
                if hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 {
                    selectedHour = hour
                    selectedMinute = minute
                }
            }
        } else if numbers.count == 2 {
            // 2桁の場合は分のみとして扱う（現在の時間の分を更新）
            if let minute = Int(numbers) {
                if minute >= 0 && minute <= 59 {
                    selectedMinute = minute
                }
            }
        } else if numbers.count == 1 {
            // 1桁の場合は分の一の位として扱う
            if let minute = Int(numbers) {
                selectedMinute = (selectedMinute / 10) * 10 + minute
                if selectedMinute > 59 {
                    selectedMinute = minute
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AlarmManager())
}
