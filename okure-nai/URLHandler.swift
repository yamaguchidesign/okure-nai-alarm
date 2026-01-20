//
//  URLHandler.swift
//  okure-nai
//
//  Created on 2025/10/12.
//

import Foundation
import AppKit

class URLHandler: NSObject {
    static let shared = URLHandler()
    var calendarService: GoogleCalendarService?
    var calendarScheduler: CalendarAlarmScheduler?
    
    override init() {
        super.init()
    }
    
    func setup() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }
    
    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        
        // OAuthコールバックを処理
        if url.scheme == "com.yamaguchi.okure-nai" {
            Task {
                await handleOAuthCallback(url: url)
            }
        }
    }
    
    private func handleOAuthCallback(url: URL) async {
        guard let calendarService = calendarService else {
            return
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return
        }
        
        var code: String?
        var state: String?
        var error: String?
        
        for item in queryItems {
            switch item.name {
            case "code":
                code = item.value
            case "state":
                state = item.value
            case "error":
                error = item.value
            default:
                break
            }
        }
        
        if let error = error {
            print("OAuthエラー: \(error)")
            return
        }
        
        guard let code = code, let state = state else {
            return
        }
        
        do {
            try await calendarService.exchangeCodeForToken(code: code, state: state)
            
            // 認証成功後、カレンダー連携を有効化
            await MainActor.run {
                if let scheduler = calendarScheduler, !scheduler.isEnabled {
                    scheduler.enable()
                }
            }
        } catch {
            print("トークン交換エラー: \(error.localizedDescription)")
        }
    }
}
