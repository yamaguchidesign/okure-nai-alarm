//
//  AlarmModel.swift
//  okure-nai
//
//  Created by 山口翔平 on 2025/10/12.
//

import Foundation
import SwiftUI
import Combine

// 曜日列挙型
enum Weekday: Int, CaseIterable, Codable {
    case sunday = 1
    case monday = 2
    case tuesday = 3
    case wednesday = 4
    case thursday = 5
    case friday = 6
    case saturday = 7
    
    var displayName: String {
        switch self {
        case .sunday: return "日"
        case .monday: return "月"
        case .tuesday: return "火"
        case .wednesday: return "水"
        case .thursday: return "木"
        case .friday: return "金"
        case .saturday: return "土"
        }
    }
    
    var fullDisplayName: String {
        switch self {
        case .sunday: return "日曜日"
        case .monday: return "月曜日"
        case .tuesday: return "火曜日"
        case .wednesday: return "水曜日"
        case .thursday: return "木曜日"
        case .friday: return "金曜日"
        case .saturday: return "土曜日"
        }
    }
}

// アラームデータモデル
struct Alarm: Identifiable, Codable {
    let id = UUID()
    var hour: Int
    var minute: Int
    var isEnabled: Bool = true
    var weekdays: Set<Weekday> = []
    
    var timeString: String {
        return String(format: "%02d:%02d", hour, minute)
    }
    
    var date: Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }
    
    var isRecurring: Bool {
        return !weekdays.isEmpty
    }
    
    var weekdayDisplayString: String {
        if weekdays.isEmpty {
            return "一回限り"
        } else if weekdays.count == 7 {
            return "毎日"
        } else if weekdays == Set([Weekday.monday, .tuesday, .wednesday, .thursday, .friday]) {
            return "平日"
        } else if weekdays == Set([Weekday.saturday, .sunday]) {
            return "週末"
        } else {
            let sortedWeekdays = weekdays.sorted { $0.rawValue < $1.rawValue }
            return sortedWeekdays.map { $0.displayName }.joined(separator: ",")
        }
    }
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
    
    private func saveAlarms() {
        if let encoded = try? JSONEncoder().encode(alarms) {
            userDefaults.set(encoded, forKey: alarmsKey)
        }
    }
    
    private func loadAlarms() {
        if let data = userDefaults.data(forKey: alarmsKey),
           let decoded = try? JSONDecoder().decode([Alarm].self, from: data) {
            alarms = decoded
        }
    }
    
    func getEnabledAlarms() -> [Alarm] {
        return alarms.filter { $0.isEnabled }
    }
}
