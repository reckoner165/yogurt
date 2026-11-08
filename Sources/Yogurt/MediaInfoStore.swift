import Foundation

/// Loads `MediaInfo` for the open file: header-level details first, then the
/// slower full-decode level analysis.
@MainActor
final class MediaInfoStore: ObservableObject {
    @Published private(set) var info = MediaInfo()
    @Published private(set) var isMeasuringLevels = false

    private var task: Task<Void, Never>?

    func load(url: URL) {
        task?.cancel()
        info = MediaInfo()
        isMeasuringLevels = true
        task = Task { [weak self] in
            let basic = await MediaInfo.load(url: url)
            guard !Task.isCancelled else { return }
            self?.info = basic

            // Off the main actor; cancelled along with this task when another file opens.
            let measure = Task.detached(priority: .utility) {
                await AudioLevels.measure(url: url)
            }
            let levels = await withTaskCancellationHandler {
                await measure.value
            } onCancel: {
                measure.cancel()
            }
            guard !Task.isCancelled, let self else { return }
            self.info.levels = levels
            self.isMeasuringLevels = false
        }
    }
}
