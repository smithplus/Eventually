import SwiftUI

struct PopoverView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var tasksService: GoogleTasksService
    @EnvironmentObject var shortcutManager: ShortcutManager

    var body: some View {
        Group {
            if authService.isAuthenticated {
                TasksView()
            } else {
                LoginView()
            }
        }
        .frame(width: 360)
    }
}

// MARK: - Login View

struct LoginView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checklist")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("Eventually")
                    .font(.title2.bold())
                Text("Google Tasks in your menu bar")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let error = authService.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                authService.signIn()
            } label: {
                HStack(spacing: 8) {
                    if authService.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "person.badge.key")
                    }
                    Text("Sign in with Google")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(authService.isLoading)
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(height: 300)
        .padding()
    }
}
