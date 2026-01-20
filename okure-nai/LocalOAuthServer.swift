//
//  LocalOAuthServer.swift
//  okure-nai
//
//  Created on 2025/10/12.
//

import Foundation
import Network

// ローカルOAuthサーバー（リダイレクトURIを処理）
class LocalOAuthServer {
    private var listener: NWListener?
    private let port: UInt16 = 8080
    var onCallback: ((URL) -> Void)?
    
    func start() {
        let parameters = NWParameters.tcp
        let portValue = NWEndpoint.Port(rawValue: port)!
        
        do {
            listener = try NWListener(using: parameters, on: portValue)
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: .main)
            print("OAuthサーバーがポート\(port)で起動しました")
        } catch {
            print("OAuthサーバーの起動に失敗: \(error)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            if let data = data, let requestString = String(data: data, encoding: .utf8) {
                self?.handleRequest(requestString, connection: connection)
            }
            
            if isComplete {
                connection.cancel()
            }
        }
    }
    
    private func handleRequest(_ request: String, connection: NWConnection) {
        // HTTPリクエストを解析
        let lines = request.components(separatedBy: "\r\n")
        guard let firstLine = lines.first else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }
        
        let components = firstLine.components(separatedBy: " ")
        guard components.count >= 2 else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }
        
        let path = components[1]
        
        // OAuthコールバックを処理
        if path.hasPrefix("/oauth2callback") {
            if let url = URL(string: "http://localhost:8080\(path)") {
                // メインスレッドでコールバックを実行
                DispatchQueue.main.async {
                    self.onCallback?(url)
                }
            }
            
            // 成功ページを表示
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <title>認証成功</title>
                <meta charset="UTF-8">
            </head>
            <body>
                <h1>認証が完了しました</h1>
                <p>このウィンドウを閉じて、アプリに戻ってください。</p>
                <script>
                    setTimeout(function() {
                        window.close();
                    }, 2000);
                </script>
            </body>
            </html>
            """
            sendResponse(connection: connection, statusCode: 200, body: html, contentType: "text/html; charset=utf-8")
        } else {
            sendResponse(connection: connection, statusCode: 404, body: "Not Found")
        }
    }
    
    private func sendResponse(connection: NWConnection, statusCode: Int, body: String, contentType: String = "text/plain") {
        let statusText = statusCode == 200 ? "OK" : statusCode == 400 ? "Bad Request" : "Not Found"
        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    print("レスポンス送信エラー: \(error)")
                }
                connection.cancel()
            })
        }
    }
}
