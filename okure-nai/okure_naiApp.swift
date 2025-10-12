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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(alarmManager)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        
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
