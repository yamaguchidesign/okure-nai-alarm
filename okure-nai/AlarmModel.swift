//
//  AlarmModel.swift
//  okure-nai
//
//  Created by 山口翔平 on 2025/10/12.
//

import Foundation
import SwiftUI
import Combine

// アラームデータモデル
struct Alarm: Identifiable, Codable {
    let id = UUID()
    var hour: Int
    var minute: Int
    var isEnabled: Bool = true
    
    var timeString: String {
        return String(format: "%02d:%02d", hour, minute)
    }
    
    var date: Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
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
