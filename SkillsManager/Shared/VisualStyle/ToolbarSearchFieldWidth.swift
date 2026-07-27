import AppKit
import SwiftUI

extension View {
    /// Caps the width of the window's toolbar search field.
    ///
    /// `searchable(placement: .toolbar)` lets the macOS search field grow until it is
    /// wider than every toolbar action combined, which inverts the toolbar's hierarchy.
    /// SwiftUI exposes no width control, so this bridges to the `NSSearchToolbarItem`
    /// backing it. Apply the modifier to any view inside the window; the toolbar item is
    /// resolved once that view has a window.
    ///
    /// - Parameter width: The maximum width, in points, for the search field.
    func toolbarSearchFieldWidth(_ width: CGFloat) -> some View {
        background(ToolbarSearchFieldWidthBridge(width: width))
    }
}

private struct ToolbarSearchFieldWidthBridge: NSViewRepresentable {
    let width: CGFloat

    func makeNSView(context: Context) -> ToolbarSearchFieldWidthView {
        ToolbarSearchFieldWidthView(width: width)
    }

    func updateNSView(_ nsView: ToolbarSearchFieldWidthView, context: Context) {
        nsView.width = width
    }
}

/// A zero-sized view whose only job is to notice when it joins a window so it can cap
/// that window's search toolbar item.
private final class ToolbarSearchFieldWidthView: NSView {
    var width: CGFloat {
        didSet {
            guard width != oldValue else {
                return
            }
            widthConstraint?.constant = width
            applyWidth()
        }
    }

    private var widthConstraint: NSLayoutConstraint?

    init(width: CGFloat) {
        self.width = width
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        .zero
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyWidth()
    }

    /// The toolbar item is built while the window is being assembled, so a single pass
    /// can run before it exists. Retry on later run loop turns until it is found.
    private func applyWidth(remainingAttempts: Int = 10) {
        if configureSearchItem() || remainingAttempts <= 0 {
            return
        }

        Task { @MainActor [weak self] in
            self?.applyWidth(remainingAttempts: remainingAttempts - 1)
        }
    }

    private func configureSearchItem() -> Bool {
        guard
            let searchItem = window?.toolbar?.items
                .lazy
                .compactMap({ $0 as? NSSearchToolbarItem })
                .first
        else {
            return false
        }

        searchItem.preferredWidthForSearchField = width

        // SwiftUI's search item ignores `preferredWidthForSearchField`, so the field
        // itself carries the cap. `lessThanOrEqual` keeps the system free to collapse
        // the field into its magnifying-glass button when the toolbar runs out of room.
        if widthConstraint == nil {
            let constraint = searchItem.searchField.widthAnchor.constraint(
                lessThanOrEqualToConstant: width
            )
            constraint.isActive = true
            widthConstraint = constraint
        }

        return true
    }
}
