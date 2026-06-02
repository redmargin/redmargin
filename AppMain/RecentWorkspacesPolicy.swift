import Foundation

enum RecentWorkspacesPolicy {
    static func shouldShowAtLaunch(
        restoredLocalCount: Int,
        restoredRemoteCount: Int,
        restoredFolderCount: Int,
        launchedWithFiles: Bool,
        hasPendingRemoteLaunches: Bool,
        settingEnabled: Bool
    ) -> Bool {
        restoredLocalCount == 0
            && restoredRemoteCount == 0
            && restoredFolderCount == 0
            && !launchedWithFiles
            && !hasPendingRemoteLaunches
            && settingEnabled
    }
}
