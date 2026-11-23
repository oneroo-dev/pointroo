import Foundation

/// Which main window the app shows: the kit window (web screens) or the old SwiftUI one.
enum MainWindowChoice: Equatable {
    case kit
    case classic

    /// The kit window needs the setting on and the built screens (or a dev address) to be there; otherwise keep the classic window.
    static func decide(kitWindow: Bool, uiAvailable: Bool) -> MainWindowChoice {
        kitWindow && uiAvailable ? .kit : .classic
    }
}

/// Swaps the main window when the choice changes while the app runs. It swaps only when the wanted choice differs from the one shown,
/// and it records the new choice before it swaps, so a change made by the swap itself (saving a window frame writes UserDefaults)
/// does not start a second swap.
@MainActor
final class MainWindowSwapper {
    private(set) var shown: MainWindowChoice
    private let wanted: () -> MainWindowChoice
    private let swap: (MainWindowChoice) -> Void

    init(shown: MainWindowChoice, wanted: @escaping () -> MainWindowChoice, swap: @escaping (MainWindowChoice) -> Void) {
        self.shown = shown
        self.wanted = wanted
        self.swap = swap
    }

    /// Call when a setting may have changed. Returns true when the window was swapped.
    @discardableResult
    func settingsMayHaveChanged() -> Bool {
        let target = wanted()
        guard target != shown else { return false }
        shown = target
        swap(target)
        return true
    }
}
