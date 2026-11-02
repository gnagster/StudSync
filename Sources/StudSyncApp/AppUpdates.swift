import Combine
import Foundation
import Observation
import Sparkle

@MainActor @Observable
final class AppUpdates {
    static let shared = AppUpdates()
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    private var observation: AnyCancellable?
    private(set) var canCheck = false

    func start() {
        controller.startUpdater()
        observation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in self?.canCheck = value }
    }

    func check() { controller.checkForUpdates(nil) }

    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
    var automaticallyDownloads: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }
}
