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
    @State private var selectedHour = Calendar.current.component(.hour, from: Date())
    @State private var selectedMinute = Calendar.current.component(.minute, from: Date())
    @State private var alarmTime: Date?
    @State private var isAlarmSet = false
    @State private var currentTime = Date()
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            VStack(spacing: 20) {
                Text("アラーム時刻を設定")
                    .font(.headline)
                
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
                
                if isAlarmSet, let alarm = alarmTime {
                    VStack(spacing: 10) {
                        Text("設定中のアラーム")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(alarm, style: .time)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(.blue)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(15)
                }
                
                HStack(spacing: 20) {
                    Button(action: setAlarm) {
                        Text(isAlarmSet ? "アラームを更新" : "アラームを設定")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 180, height: 50)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    
                    if isAlarmSet {
                        Button(action: cancelAlarm) {
                            Text("キャンセル")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 120, height: 50)
                                .background(Color.red)
                                .cornerRadius(10)
                        }
                    }
                }
            }
            
            Spacer()
            
            Text("現在時刻: \(currentTime, style: .time)")
                .font(.title2)
                .foregroundColor(.secondary)
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { _ in
            currentTime = Date()
            checkAlarm()
        }
        .onChange(of: alarmManager.showAlarmPanel) { showing in
            // アラームパネルが閉じられたら、ローカルの状態もリセット
            if !showing && alarmManager.alarmTime == nil {
                isAlarmSet = false
                alarmTime = nil
            }
        }
    }
    
    func setAlarm() {
        var components = DateComponents()
        components.hour = selectedHour
        components.minute = selectedMinute
        
        if let date = Calendar.current.date(from: components) {
            alarmTime = date
            isAlarmSet = true
            
            // 通知権限をリクエスト
            requestNotificationPermission()
        }
    }
    
    func cancelAlarm() {
        alarmTime = nil
        isAlarmSet = false
        alarmManager.dismissAlarm()
    }
    
    func checkAlarm() {
        guard let alarm = alarmTime, isAlarmSet else { return }
        guard !alarmManager.showAlarmPanel else { return }
        
        let calendar = Calendar.current
        let currentComponents = calendar.dateComponents([.hour, .minute], from: currentTime)
        let alarmComponents = calendar.dateComponents([.hour, .minute], from: alarm)
        
        if currentComponents.hour == alarmComponents.hour &&
           currentComponents.minute == alarmComponents.minute {
            triggerAlarm()
        }
    }
    
    func triggerAlarm() {
        guard let alarm = alarmTime else { return }
        
        // アラームマネージャーを通じてアラームを発動
        alarmManager.triggerAlarm(time: alarm)
        
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

#Preview {
    ContentView()
        .environmentObject(AlarmManager())
}
