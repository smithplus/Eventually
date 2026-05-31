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
    @AppStorage("panelPosition") private var panelPosition = "center"
    @AppStorage("defaultCommandView") private var defaultCommandView = "today"
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { value in
                    LaunchAtLogin.set(value)
                }
            Toggle("Show task count badge", isOn: $showBadgeCount)

            Picker("Appearance:", selection: $appearance) {
                ForEach(Appearance.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: appearance) { _ in applyAppearance() }

            Picker("Command Window position:", selection: $panelPosition) {
                Text("Left").tag("left")
                Text("Center").tag("center")
                Text("Right").tag("right")
            }
            .pickerStyle(.segmented)
            .onChange(of: panelPosition) { _ in
                // Choosing a position overrides a remembered manual location.
                UserDefaults.standard.set(false, forKey: DefaultsKey.panelHasSavedFrame)
            }

            Picker("Command Window opens to:", selection: $defaultCommandView) {
                Text("Today").tag("today")
                Text("Upcoming").tag("upcoming")
                Text("All Tasks").tag("all")
                Text("Last used").tag("lastUsed")
            }
        }
        .padding()
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
