//
//  CalendarAlarmScheduler.swift
//  okure-nai
//
//  Created on 2025/10/12.
//

import Foundation
import Combine

// カレンダー連携アラーム管理クラス
class CalendarAlarmScheduler: ObservableObject {
    @Published var isEnabled = false
    @Published var onlyEventsWithGuests = true
    @Published var lastSyncDate: Date?
    @Published var nextCheckDate: Date?
    
    private let calendarService: GoogleCalendarService
    private let alarmStore: AlarmStore
    private var dailyCheckTimer: Timer?
    private let calendarAlarmPrefix = "calendar_"
    
    init(calendarService: GoogleCalendarService, alarmStore: AlarmStore) {
        self.calendarService = calendarService
        self.alarmStore = alarmStore
        
        // 設定を読み込む
        loadSettings()
        
        // 既存のカレンダーアラームをクリーンアップ
        cleanupOldCalendarAlarms()
        
        // 有効な場合、定期チェックを開始
        if isEnabled {
            startDailyCheck()
        }
    }
    
    // 設定を読み込む
    private func loadSettings() {
        isEnabled = UserDefaults.standard.bool(forKey: "CalendarAlarmEnabled")
        // 既存ユーザーは「従来通り全予定」でも使えるように、未設定時はtrue（今回のデフォルト）
        if UserDefaults.standard.object(forKey: "CalendarAlarmOnlyEventsWithGuests") == nil {
            onlyEventsWithGuests = true
        } else {
            onlyEventsWithGuests = UserDefaults.standard.bool(forKey: "CalendarAlarmOnlyEventsWithGuests")
        }
        if let lastSync = UserDefaults.standard.object(forKey: "CalendarAlarmLastSync") as? Date {
            lastSyncDate = lastSync
        }
    }
    
    // 設定を保存
    private func saveSettings() {
        UserDefaults.standard.set(isEnabled, forKey: "CalendarAlarmEnabled")
        UserDefaults.standard.set(onlyEventsWithGuests, forKey: "CalendarAlarmOnlyEventsWithGuests")
        if let lastSync = lastSyncDate {
            UserDefaults.standard.set(lastSync, forKey: "CalendarAlarmLastSync")
        }
    }
    
    // カレンダー連携を有効化
    func enable() {
        guard calendarService.isAuthenticated else {
            return
        }
        
        isEnabled = true
        saveSettings()
        startDailyCheck()
        
        // 即座に今日の予定をチェック
        Task {
            await syncTodayAlarms()
        }
    }
    
    // カレンダー連携を無効化
    func disable() {
        isEnabled = false
        saveSettings()
        stopDailyCheck()
        
        // カレンダーアラームを削除
        removeAllCalendarAlarms()
    }
    
    // 毎日00:00にチェックするタイマーを開始
    private func startDailyCheck() {
        stopDailyCheck()
        
        // 次の00:00を計算
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 0
        components.minute = 0
        components.second = 1
        
        var nextMidnight = calendar.date(from: components)!
        if nextMidnight <= now {
            nextMidnight = calendar.date(byAdding: .day, value: 1, to: nextMidnight)!
        }
        
        nextCheckDate = nextMidnight
        
        // タイマーを設定
        let timeInterval = nextMidnight.timeIntervalSince(now)
        dailyCheckTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            Task {
                await self?.syncTodayAlarms()
            }
            // 次の日の00:00のタイマーを再設定
            self?.scheduleNextDailyCheck()
        }
    }
    
    // 次の日の00:00のタイマーを設定
    private func scheduleNextDailyCheck() {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 0
        components.minute = 0
        components.second = 1
        
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.date(from: components)!)!
        nextCheckDate = nextMidnight
        
        let timeInterval = nextMidnight.timeIntervalSince(now)
        dailyCheckTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: false) { [weak self] _ in
            Task {
                await self?.syncTodayAlarms()
            }
            self?.scheduleNextDailyCheck()
        }
    }
    
    // タイマーを停止
    private func stopDailyCheck() {
        dailyCheckTimer?.invalidate()
        dailyCheckTimer = nil
    }
    
    // 今日の予定を同期してアラームを設定
    func syncTodayAlarms() async {
        guard isEnabled, calendarService.isAuthenticated else {
            return
        }
        
        // 古いカレンダーアラームを削除
        removeAllCalendarAlarms()
        
        do {
            let events = try await calendarService.fetchTodayEvents()
            
            await MainActor.run {
                // 各イベントの開始時刻の2分前にアラームを設定
                for event in events {
                    // 「ゲストがいる予定でのみアラームを有効にする」設定がONの場合のみフィルタ
                    if onlyEventsWithGuests && guestCountExcludingSelf(event) < 1 {
                        continue
                    }
                    guard let startDate = event.start.startDate else { continue }
                    
                    // 開始時刻が未来であることを確認
                    if startDate <= Date() {
                        continue
                    }
                    
                    // 2分前の時刻を計算
                    let alarmDate = startDate.addingTimeInterval(-2 * 60)
                    
                    // アラームが未来であることを確認
                    if alarmDate <= Date() {
                        continue
                    }
                    
                    let calendar = Calendar.current
                    let components = calendar.dateComponents([.hour, .minute], from: alarmDate)
                    
                    guard let hour = components.hour,
                          let minute = components.minute else {
                        continue
                    }
                    
                    // カレンダーアラームを作成（一回限り、isCalendarAlarm=true）
                    let title = event.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                    let displayTitle = title.isEmpty ? nil : title
                    let calendarAlarm = Alarm(
                        hour: hour,
                        minute: minute,
                        isEnabled: true,
                        isCalendarAlarm: true,
                        calendarEventTitle: displayTitle
                    )
                    
                    alarmStore.addCalendarAlarm(calendarAlarm)
                }
                
                lastSyncDate = Date()
                saveSettings()
            }
        } catch {
            print("カレンダー同期エラー: \(error.localizedDescription)")
        }
    }

    private func guestCountExcludingSelf(_ event: CalendarEvent) -> Int {
        guard let attendees = event.attendees else { return 0 }

        var count = 0
        for attendee in attendees {
            // 自分は除外
            if attendee.`self` == true { continue }

            // declinedは除外。それ以外(accepted/tentative/needsAction/不明)はカウント
            if let status = attendee.responseStatus, status == "declined" { continue }

            count += 1
        }
        return count
    }
    
    // 古いカレンダーアラームを削除
    private func removeAllCalendarAlarms() {
        alarmStore.removeCalendarAlarms()
    }
    
    // 古いカレンダーアラームをクリーンアップ（過去の日付のもの）
    private func cleanupOldCalendarAlarms() {
        let now = Date()
        let calendar = Calendar.current
        let nowComponents = calendar.dateComponents([.hour, .minute], from: now)
        
        // カレンダーアラームで、時刻が過去のものを削除
        let alarmsToRemove = alarmStore.alarms.filter { alarm in
            guard alarm.isCalendarAlarm else { return false }
            
            // 時刻が過去かどうかをチェック
            if alarm.hour < nowComponents.hour ?? 0 {
                return true
            }
            if alarm.hour == nowComponents.hour ?? 0 && alarm.minute < nowComponents.minute ?? 0 {
                return true
            }
            
            return false
        }
        
        for alarm in alarmsToRemove {
            alarmStore.deleteAlarm(alarm)
        }
    }
}
