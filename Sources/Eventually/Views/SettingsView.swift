import SwiftUI
import KeyboardShortcuts
import ServiceManagement

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
    @AppStorage(DefaultsKey.launchAtLogin) private var launchAtLogin = false
    @AppStorage(DefaultsKey.showBadgeCount) private var showBadgeCount = true
    @AppStorage(DefaultsKey.showMenuBarIcon) private var showMenuBarIcon = true
    @AppStorage(DefaultsKey.panelPosition) private var panelPosition = "center"
    @AppStorage(DefaultsKey.defaultCommandView) private var defaultCommandView = "today"
    @AppStorage(DefaultsKey.appearance) private var appearance = "system"
    @AppStorage(DefaultsKey.autoRefreshMinutes) private var autoRefreshMinutes = 15

    var body: some View {
        Form {
            Section("Menu bar") {
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                    .onChange(of: showMenuBarIcon) { _ in
                        NotificationCenter.default.post(name: .menuBarIconSettingChanged, object: nil)
                    }
                Toggle("Show task count badge", isOn: $showBadgeCount)
                    .onChange(of: showBadgeCount) { _ in
                        NotificationCenter.default.post(name: .badgeSettingChanged, object: nil)
                    }
                Text("The Command Window also opens with the ⌘⇧O shortcut, even with the icon hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LaunchAtLogin.set($0) }
            }

            Section("Appearance") {
                Picker("Theme:", selection: $appearance) {
                    ForEach(Appearance.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: appearance) { _ in applyAppearance() }
            }

            Section("Sync") {
                Picker("Auto-refresh:", selection: $autoRefreshMinutes) {
                    Text("Off").tag(0)
                    Text("Every 5 min").tag(5)
                    Text("Every 15 min").tag(15)
                    Text("Every 30 min").tag(30)
                }
                .onChange(of: autoRefreshMinutes) { _ in
                    NotificationCenter.default.post(name: .autoRefreshChanged, object: nil)
                }
            }

            Section("Command Window") {
                Picker("Position:", selection: $panelPosition) {
                    Text("Left").tag("left")
                    Text("Center").tag("center")
                    Text("Right").tag("right")
                }
                .pickerStyle(.segmented)
                .onChange(of: panelPosition) { _ in
                    // Choosing a position overrides a remembered manual location.
                    UserDefaults.standard.set(false, forKey: DefaultsKey.panelHasSavedFrame)
                }

                Picker("Opens to:", selection: $defaultCommandView) {
                    Text("Today").tag("today")
                    Text("Upcoming").tag("upcoming")
                    Text("All Tasks").tag("all")
                    Text("Last used").tag("lastUsed")
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            // Reflect the real launch-at-login status (may have changed elsewhere).
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsSettingsTab: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Open Command Window:", name: .openCommandWindow)
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
                    .foregroundStyle(Theme.accent)

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

            Spacer()

            // Version info
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
               let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
                VStack(spacing: 4) {
                    Text("Eventually v\(version) (build \(build))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Built \(buildDateString())")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func buildDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}

// MARK: - Launch at Login (ServiceManagement)

enum LaunchAtLogin {
    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("LaunchAtLogin failed: \(error.localizedDescription)")
        }
    }

    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
