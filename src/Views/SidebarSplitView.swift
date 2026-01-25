import SwiftUI
import AppKit

/// A SwiftUI view that provides a collapsible sidebar alongside main content
public struct SidebarSplitView<Sidebar: View, Content: View>: View {
    let sidebar: () -> Sidebar
    let content: () -> Content
    @Binding var isSidebarVisible: Bool
    @Binding var sidebarWidth: CGFloat

    private let minWidth: CGFloat = 150
    private let maxWidth: CGFloat = 400

    public init(
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder content: @escaping () -> Content,
        isSidebarVisible: Binding<Bool>,
        sidebarWidth: Binding<CGFloat>
    ) {
        self.sidebar = sidebar
        self.content = content
        self._isSidebarVisible = isSidebarVisible
        self._sidebarWidth = sidebarWidth
    }

    public var body: some View {
        HStack(spacing: 0) {
            if isSidebarVisible {
                sidebar()
                    .frame(width: sidebarWidth)
                    .background(Color(nsColor: .windowBackgroundColor))

                SidebarDivider(width: $sidebarWidth, minWidth: minWidth, maxWidth: maxWidth)
            }

            content()
        }
    }
}

/// A draggable divider for resizing the sidebar
private struct SidebarDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .contentShape(Rectangle().inset(by: -4))
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let newWidth = width + value.translation.width
                        width = max(minWidth, min(maxWidth, newWidth))
                    }
                    .onEnded { _ in
                        isDragging = false
                        NSCursor.pop()
                    }
            )
    }
}
