import AppKit
import Sparkle

/// Sparkle stays linked, but Pointroo has no update feed: nothing checks or downloads unless a feed is set on purpose
/// (SUFeedURL in Info.plist, or `defaults write dev.oneroodev.pointroo updateFeedURL <url>` for a test feed).
@MainActor
final class Updater: NSObject, SPUUpdaterDelegate {
    static let shared = Updater()
    private var controller: SPUStandardUpdaterController?
    private var installNow: (() -> Void)?
    weak var state: AppState?

    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }

    var hasFeed: Bool {
        UserDefaults.standard.string(forKey: "updateFeedURL") != nil || Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
    }

    func start(state: AppState) {
        self.state = state
        guard hasFeed, AgentInstall.installed, controller == nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
    }

    func checkNow() {
        if let controller { controller.checkForUpdates(nil) } else { state?.showToast("Updates are off in Pointroo") }
    }

    /// Restart into the downloaded version.
    func restart() {
        Relaunch.cancel()
        installNow?()
    }

    // MARK: SPUUpdaterDelegate

    /// A test feed for checking an update end to end (`defaults write dev.oneroodev.pointroo updateFeedURL <url>`);
    /// the download must still carry a valid signature.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: "updateFeedURL")
    }

    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock: @escaping () -> Void) -> Bool {
        let v = item.displayVersionString
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.installNow = immediateInstallationBlock
                self.state?.updateReady = v
            }
        }
        return true   // we show it ourselves; Sparkle still installs on quit
    }
}
