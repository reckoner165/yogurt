import Foundation
import Combine

/// Feeds the status bar. Display priority: hover hint > transient event > idle text.
@MainActor
final class StatusCenter: ObservableObject {
    @Published private(set) var display: String = ""

    private var idleText = ""
    private var transientText: String?
    private var hintText: String?
    private var clearItem: DispatchWorkItem?

    func setIdle(_ text: String) {
        idleText = text
        refresh()
    }

    func transient(_ text: String, seconds: Double = 4) {
        transientText = text
        clearItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.transientText = nil
            self?.refresh()
        }
        clearItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        refresh()
    }

    func hint(_ text: String?) {
        hintText = text
        refresh()
    }

    private func refresh() {
        display = hintText ?? transientText ?? idleText
    }
}
