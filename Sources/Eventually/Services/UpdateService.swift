import Foundation
import Sparkle

/// Manages automatic app updates via Sparkle.
/// The appcast URL points to the GitHub releases feed for this repo.
/// @MainActor ensures all @Published mutations and Sparkle callbacks stay on the main thread.
@MainActor
final class UpdateService: NSObject, ObservableObject, SPUUpdaterDelegate {

    static let shared = UpdateService()

    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    private override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
        canCheckForUpdates = updaterController.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
