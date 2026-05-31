import SwiftUI

// MARK: - Login View (shown inside the Command Window when signed out)

struct LoginView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checklist")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Theme.accent)

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
            .buttonStyle(CapsuleButton(enabled: !authService.isLoading))
            .disabled(authService.isLoading)
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(height: 300)
        .padding()
    }
}
