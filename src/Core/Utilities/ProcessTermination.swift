import Foundation

extension Process {
    func terminateIfRunning() {
        guard isRunning else { return }
        terminate()
    }
}
