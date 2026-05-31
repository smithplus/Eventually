import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }

            ShortcutsSettingsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }

            AccountSettingsTab()
                .tabItem { Label("Account", systemImage: "person.circle") }
        }
        .frame(width: 420, height: 300)
        .padding()
    }
}

// MARK: - General

struct GeneralSettingsTab: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showBadgeCount") private var showBadgeCount = true

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, value in
                    LaunchAtLogin.set(value)
                }
            Toggle("Show task count badge", isOn: $showBadgeCount)
        }
        .padding()
    }
}

// MARK: - Shortcuts

struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Open Eventually:", name: .openEventually)
            KeyboardShortcuts.Recorder("Open & add task:", name: .openAndAddTask)
        }
        .padding()
    }
}

// MARK: - Account

struct AccountSettingsTab: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        VStack(spacing: 16) {
            if authService.isAuthenticated {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                Text(authService.userEmail ?? "Signed in to Google")
                    .font(.headline)

                Button("Sign Out", role: .destructive) {
                    authService.signOut()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Text("Not signed in")
                    .foregroundStyle(.secondary)
                Button("Sign In") {
                    authService.signIn()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Launch at Login helper (stub — use ServiceManagement in real impl)
enum LaunchAtLogin {
    static func set(_ enabled: Bool) {
        // In production: use SMAppService.mainApp.register() / .unregister()
        // Requires macOS 13+ and proper entitlements
    }
}
