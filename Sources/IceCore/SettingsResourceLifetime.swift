import Foundation

@MainActor
public final class SettingsResourceLifetime {
    private enum State { case unused, open, closed, released }
    private var state = State.unused
    private var pressureElevated = false
    private var pending: Task<Void, Never>?
    private let delay: Duration
    private let release: @MainActor () -> Void

    public init(delay: Duration = .seconds(180), release: @escaping @MainActor () -> Void) {
        self.delay = delay
        self.release = release
    }

    deinit { pending?.cancel() }

    public func opened() {
        pending?.cancel()
        pending = nil
        state = .open
    }

    public func closed() {
        guard state == .open else { return }
        state = .closed
        schedule(after: pressureElevated ? .zero : delay)
    }

    public func memoryPressureChanged(isElevated: Bool) {
        pressureElevated = isElevated
        if isElevated && state == .closed { schedule(after: .zero) }
    }

    private func schedule(after interval: Duration) {
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: interval) } catch { return }
            guard !Task.isCancelled, let self, self.state == .closed else { return }
            self.pending = nil
            self.state = .released
            self.release()
        }
    }
}
