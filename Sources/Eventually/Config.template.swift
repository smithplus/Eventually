import Foundation

// Copy this file to Config.swift and fill in your credentials.
// Config.swift is git-ignored — never commit real credentials.
//
// How to get credentials:
// 1. Go to https://console.cloud.google.com
// 2. Create a project → Enable "Google Tasks API"
// 3. Credentials → OAuth 2.0 Client ID → macOS → bundle: app.tabella.Eventually
// 4. Copy Client ID and Secret below

enum GoogleConfig {
    static let clientId = "YOUR_CLIENT_ID.apps.googleusercontent.com"
    static let clientSecret = "YOUR_CLIENT_SECRET"
}
