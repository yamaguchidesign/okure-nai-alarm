//
//  GoogleCalendarService.swift
//  okure-nai
//
//  Created on 2025/10/12.
//

import Foundation
import Combine

// Google Calendar API イベントモデル
struct CalendarEvent: Identifiable, Codable {
    let id: String
    let summary: String
    let start: EventDateTime
    let end: EventDateTime?
    
    struct EventDateTime: Codable {
        let dateTime: String?
        let date: String?
        
        var startDate: Date? {
            if let dateTime = dateTime {
                return ISO8601DateFormatter().date(from: dateTime)
            } else if let date = date {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.timeZone = TimeZone.current
                return formatter.date(from: date)
            }
            return nil
        }
    }
}

// Google Calendar API レスポンス
struct CalendarEventsResponse: Codable {
    let items: [CalendarEvent]?
}

// Google Calendar サービス
class GoogleCalendarService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private var clientId: String {
        return UserDefaults.standard.string(forKey: "GoogleCalendarClientId") ?? ""
    }
    
    private var clientSecret: String {
        return UserDefaults.standard.string(forKey: "GoogleCalendarClientSecret") ?? ""
    }
    
    private let redirectURI: String
    private let tokenKey = "GoogleCalendarAccessToken"
    private let refreshTokenKey = "GoogleCalendarRefreshToken"
    private let tokenExpiryKey = "GoogleCalendarTokenExpiry"
    private let localServer = LocalOAuthServer()
    
    private var accessToken: String? {
        get {
            return UserDefaults.standard.string(forKey: tokenKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: tokenKey)
        }
    }
    
    private var refreshToken: String? {
        get {
            return UserDefaults.standard.string(forKey: refreshTokenKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: refreshTokenKey)
        }
    }
    
    private var tokenExpiry: Date? {
        get {
            return UserDefaults.standard.object(forKey: tokenExpiryKey) as? Date
        }
        set {
            UserDefaults.standard.set(newValue, forKey: tokenExpiryKey)
        }
    }
    
    init() {
        // macOSアプリでは、ローカルホストのリダイレクトURIを使用
        // Google Cloud Consoleでhttp://localhost:8080/oauth2callbackを登録する必要があります
        self.redirectURI = "http://localhost:8080/oauth2callback"
        
        // ローカルサーバーを設定
        localServer.onCallback = { [weak self] url in
            Task {
                await self?.handleOAuthCallback(url: url)
            }
        }
        
        // 既存のトークンを確認
        if accessToken != nil {
            checkTokenValidity()
        }
    }
    
    // OAuthコールバックを処理
    private func handleOAuthCallback(url: URL) async {
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
            await MainActor.run {
                self.errorMessage = "認証エラー: \(error)"
            }
            return
        }
        
        guard let code = code, let state = state else {
            return
        }
        
        do {
            try await exchangeCodeForToken(code: code, state: state)
        } catch {
            print("トークン交換エラー: \(error.localizedDescription)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
            }
        }
    }
    
    // 認証URLを生成
    func getAuthorizationURL() -> URL? {
        // Client IDが設定されているか確認
        guard !clientId.isEmpty else {
            print("エラー: Client IDが設定されていません")
            return nil
        }
        
        // ローカルサーバーを起動
        localServer.start()
        
        let scope = "https://www.googleapis.com/auth/calendar.readonly"
        let state = UUID().uuidString
        UserDefaults.standard.set(state, forKey: "GoogleCalendarOAuthState")
        
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state)
        ]
        
        return components?.url
    }
    
    // OAuth認証コードからトークンを取得
    func exchangeCodeForToken(code: String, state: String) async throws {
        guard let savedState = UserDefaults.standard.string(forKey: "GoogleCalendarOAuthState"),
              savedState == state else {
            throw CalendarServiceError.invalidState
        }
        
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw CalendarServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code"
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw CalendarServiceError.tokenExchangeFailed
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let accessToken = json["access_token"] as? String,
           let expiresIn = json["expires_in"] as? Int {
            
            self.accessToken = accessToken
            self.refreshToken = json["refresh_token"] as? String
            self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
            self.isAuthenticated = true
            
            // 状態をクリア
            UserDefaults.standard.removeObject(forKey: "GoogleCalendarOAuthState")
        } else {
            throw CalendarServiceError.tokenExchangeFailed
        }
    }
    
    // トークンの有効性を確認
    private func checkTokenValidity() {
        if let expiry = tokenExpiry, expiry > Date() {
            isAuthenticated = true
        } else if refreshToken != nil {
            // リフレッシュトークンで更新を試みる
            Task {
                await refreshAccessToken()
            }
        } else {
            isAuthenticated = false
        }
    }
    
    // アクセストークンをリフレッシュ
    private func refreshAccessToken() async {
        guard let refreshToken = refreshToken else {
            isAuthenticated = false
            return
        }
        
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "client_id": clientId,
            "client_secret": clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let accessToken = json["access_token"] as? String,
               let expiresIn = json["expires_in"] as? Int {
                
                self.accessToken = accessToken
                self.tokenExpiry = Date().addingTimeInterval(TimeInterval(expiresIn))
                self.isAuthenticated = true
            } else {
                self.isAuthenticated = false
            }
        } catch {
            self.isAuthenticated = false
        }
    }
    
    // 今日のイベントを取得
    func fetchTodayEvents() async throws -> [CalendarEvent] {
        guard isAuthenticated, let token = accessToken else {
            throw CalendarServiceError.notAuthenticated
        }
        
        // トークンの有効性を確認
        if let expiry = tokenExpiry, expiry <= Date() {
            await refreshAccessToken()
            guard let newToken = accessToken else {
                throw CalendarServiceError.notAuthenticated
            }
            return try await fetchEventsWithToken(newToken)
        }
        
        return try await fetchEventsWithToken(token)
    }
    
    private func fetchEventsWithToken(_ token: String) async throws -> [CalendarEvent] {
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        let timeMin = formatter.string(from: startOfDay)
        let timeMax = formatter.string(from: endOfDay)
        
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")
        components?.queryItems = [
            URLQueryItem(name: "timeMin", value: timeMin),
            URLQueryItem(name: "timeMax", value: timeMax),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime")
        ]
        
        guard let url = components?.url else {
            throw CalendarServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CalendarServiceError.networkError
        }
        
        if httpResponse.statusCode == 401 {
            // トークンが無効な場合、リフレッシュを試みる
            await refreshAccessToken()
            if let newToken = accessToken {
                return try await fetchEventsWithToken(newToken)
            }
            throw CalendarServiceError.notAuthenticated
        }
        
        guard httpResponse.statusCode == 200 else {
            throw CalendarServiceError.networkError
        }
        
        let decoder = JSONDecoder()
        let eventsResponse = try decoder.decode(CalendarEventsResponse.self, from: data)
        
        return eventsResponse.items ?? []
    }
    
    // ログアウト
    func logout() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: "GoogleCalendarOAuthState")
    }
    
    // クライアントIDとシークレットを設定
    func setCredentials(clientId: String, clientSecret: String) {
        UserDefaults.standard.set(clientId, forKey: "GoogleCalendarClientId")
        UserDefaults.standard.set(clientSecret, forKey: "GoogleCalendarClientSecret")
    }
}

// エラー定義
enum CalendarServiceError: LocalizedError {
    case invalidURL
    case invalidState
    case tokenExchangeFailed
    case notAuthenticated
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無効なURLです"
        case .invalidState:
            return "認証状態が無効です"
        case .tokenExchangeFailed:
            return "トークンの取得に失敗しました"
        case .notAuthenticated:
            return "認証されていません"
        case .networkError:
            return "ネットワークエラーが発生しました"
        }
    }
}
