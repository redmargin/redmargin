import Foundation

/// Determines which components to refresh for a remote window.
enum RemoteRefreshRoute {
    case documentOnly
    case sidebarOnly
    case documentAndSidebar
}

/// Source of the refresh action.
enum RemoteRefreshSource {
    /// Command+R or notification-based refresh
    case commandRefresh
    /// Sidebar refresh button
    case sidebarButton
}

/// Returns the appropriate refresh route for a remote window.
///
/// - Parameters:
///   - isFolderMode: Whether the window is in folder mode (no file selected).
///   - sidebarVisible: Whether the sidebar is currently visible.
///   - source: Where the refresh was triggered from.
func remoteRefreshRoute(
    isFolderMode: Bool,
    sidebarVisible: Bool,
    source: RemoteRefreshSource
) -> RemoteRefreshRoute {
    switch source {
    case .sidebarButton:
        if isFolderMode {
            return .sidebarOnly
        }
        return .documentAndSidebar

    case .commandRefresh:
        if isFolderMode {
            return .sidebarOnly
        }
        if sidebarVisible {
            return .documentAndSidebar
        }
        return .documentOnly
    }
}
