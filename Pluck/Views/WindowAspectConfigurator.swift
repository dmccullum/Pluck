import AppKit
import QuartzCore
import SwiftUI

struct WindowAspectConfigurator: NSViewRepresentable {
    let aspectRatio: Double
    let hasVideo: Bool
    let controlsVisible: Bool
    let presentationID: UUID
    let onWindowAvailable: (NSWindow) -> Void
    let onPresentationReady: (UUID) -> Void

    func makeNSView(context: Context) -> WindowObservationView {
        let view = WindowObservationView(frame: .zero)
        view.onWindowAvailable = { window in
            applyConfiguration(to: window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ view: WindowObservationView, context: Context) {
        view.onWindowAvailable = { window in
            applyConfiguration(to: window, coordinator: context.coordinator)
        }

        if let window = view.window {
            applyConfiguration(to: window, coordinator: context.coordinator)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func applyConfiguration(to window: NSWindow, coordinator: Coordinator) {
        onWindowAvailable(window)

        // Content always runs under the title bar, as `.hiddenTitleBar` set it up.
        // Toggling this makes SwiftUI re-grow the window by the title bar height,
        // pushing it down the screen, so only the title bar's appearance changes.
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }

        if hasVideo, aspectRatio.isFinite, aspectRatio > 0 {
            configureVideoTitlebar(window, coordinator: coordinator)
            configureVideoWindow(window, aspectRatio: CGFloat(aspectRatio), coordinator: coordinator)
        } else {
            configureStandardTitlebar(window, coordinator: coordinator)
            configureDropWindow(window, coordinator: coordinator)
            coordinator.configuredAspectRatio = nil
            coordinator.configuredPresentationID = nil
            coordinator.transitionGeneration += 1
        }
    }

    private func configureStandardTitlebar(_ window: NSWindow, coordinator: Coordinator) {
        let wasTransparent = window.titlebarAppearsTransparent
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.titlebarSeparatorStyle = .automatic
        if wasTransparent {
            refreshTitlebarMaterial(in: window)
        }
        coordinator.chromeVisible = nil
        for button in windowButtons(in: window) {
            button.isHidden = false
            button.isEnabled = true
            button.alphaValue = 1
        }
    }

    private func configureVideoTitlebar(_ window: NSWindow, coordinator: Coordinator) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none

        guard coordinator.chromeVisible != controlsVisible else { return }
        coordinator.chromeVisible = controlsVisible
        let buttons = windowButtons(in: window)
        for button in buttons {
            if controlsVisible {
                if button.isHidden { button.alphaValue = 0 }
                button.isHidden = false
            }
            button.isEnabled = controlsVisible
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for button in buttons {
                button.animator().alphaValue = controlsVisible ? 1 : 0
            }
        } completionHandler: {
            DispatchQueue.main.async {
                guard coordinator.chromeVisible == false else { return }
                for button in buttons { button.isHidden = true }
            }
        }
    }

    /// Turning off `titlebarAppearsTransparent` on a visible window leaves the
    /// title bar's material stale (drawn solid, without the content blurred
    /// behind it) until the window's key state changes. Cycling each
    /// material view's state forces the redraw that a key change would.
    private func refreshTitlebarMaterial(in window: NSWindow) {
        DispatchQueue.main.async {
            guard let titlebarContainer = window.standardWindowButton(.closeButton)?.superview?.superview else { return }
            for effectView in visualEffectViews(in: titlebarContainer) {
                let state = effectView.state
                effectView.state = state == .active ? .inactive : .active
                effectView.state = state
                effectView.needsDisplay = true
            }
            titlebarContainer.needsLayout = true
            titlebarContainer.needsDisplay = true
        }
    }

    private func visualEffectViews(in view: NSView) -> [NSVisualEffectView] {
        var result = view.subviews.compactMap { $0 as? NSVisualEffectView }
        for subview in view.subviews {
            result += visualEffectViews(in: subview)
        }
        return result
    }

    private func windowButtons(in window: NSWindow) -> [NSButton] {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
            .compactMap { window.standardWindowButton($0) }
    }

    private func configureVideoWindow(_ window: NSWindow, aspectRatio: CGFloat, coordinator: Coordinator) {
        coordinator.configuredForDropState = false
        window.contentAspectRatio = NSSize(width: aspectRatio, height: 1)

        let minimumWidth: CGFloat = aspectRatio < 0.8 ? 400 : 560
        let minimumContentSize = NSSize(width: minimumWidth, height: minimumWidth / aspectRatio)
        let aspectChanged = coordinator.configuredAspectRatio != aspectRatio
        let presentationChanged = coordinator.configuredPresentationID != presentationID

        guard aspectChanged || presentationChanged else {
            applyMinimumContentSize(minimumContentSize, to: window)
            return
        }

        coordinator.configuredAspectRatio = aspectRatio
        coordinator.configuredPresentationID = presentationID
        coordinator.transitionGeneration += 1
        let transitionGeneration = coordinator.transitionGeneration

        guard aspectChanged else {
            applyMinimumContentSize(minimumContentSize, to: window)
            DispatchQueue.main.async {
                guard coordinator.transitionGeneration == transitionGeneration else { return }
                self.onPresentationReady(self.presentationID)
            }
            return
        }

        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let maxWidth = min(1_100, visibleFrame.width - 100)
        let maxHeight = min(820, visibleFrame.height - 100)

        var width: CGFloat
        var height: CGFloat

        if aspectRatio >= 1 {
            width = min(960, maxWidth)
            height = width / aspectRatio
            if height > maxHeight {
                height = maxHeight
                width = height * aspectRatio
            }
        } else {
            height = maxHeight
            width = height * aspectRatio
            if width < minimumWidth {
                width = minimumWidth
                height = width / aspectRatio
            }
            if height > maxHeight {
                height = maxHeight
                width = height * aspectRatio
            }
        }

        let oldFrame = window.frame
        let targetContentSize = NSSize(width: width, height: height)
        let targetFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize)).size
        let targetFrame = NSRect(
            x: oldFrame.midX - targetFrameSize.width / 2,
            y: oldFrame.midY - targetFrameSize.height / 2,
            width: targetFrameSize.width,
            height: targetFrameSize.height
        ).constrained(to: visibleFrame)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            window.animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            DispatchQueue.main.async {
                guard coordinator.transitionGeneration == transitionGeneration else { return }
                self.applyMinimumContentSize(minimumContentSize, to: window)
                self.onPresentationReady(self.presentationID)
            }
        }
    }

    private func configureDropWindow(_ window: NSWindow, coordinator: Coordinator) {
        // The drop area below the visible title bar is kept square.
        let titlebarHeight = window.frame.height - window.contentLayoutRect.height
        let targetFrameSize = NSSize(width: 480, height: 480 + titlebarHeight)
        window.contentAspectRatio = targetFrameSize
        let minimumContentSize = NSSize(width: 400, height: 400 + titlebarHeight)
        applyMinimumContentSize(minimumContentSize, to: window)

        guard !coordinator.configuredForDropState else { return }
        coordinator.configuredForDropState = true

        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let oldFrame = window.frame
        let targetFrame = NSRect(
            x: oldFrame.midX - targetFrameSize.width / 2,
            y: oldFrame.midY - targetFrameSize.height / 2,
            width: targetFrameSize.width,
            height: targetFrameSize.height
        )

        window.setFrame(targetFrame.constrained(to: visibleFrame), display: false, animate: false)
    }

    private func applyMinimumContentSize(_ contentSize: NSSize, to window: NSWindow) {
        window.contentMinSize = contentSize
        window.minSize = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
    }

    final class Coordinator {
        var configuredAspectRatio: CGFloat?
        var configuredPresentationID: UUID?
        var configuredForDropState = false
        var chromeVisible: Bool?
        var transitionGeneration = 0
    }
}

final class WindowObservationView: NSView {
    var onWindowAvailable: ((NSWindow) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            onWindowAvailable?(window)
        }
    }
}

private extension NSRect {
    func constrained(to bounds: NSRect) -> NSRect {
        var result = self
        if result.maxX > bounds.maxX { result.origin.x = bounds.maxX - result.width }
        if result.minX < bounds.minX { result.origin.x = bounds.minX }
        if result.maxY > bounds.maxY { result.origin.y = bounds.maxY - result.height }
        if result.minY < bounds.minY { result.origin.y = bounds.minY }
        return result
    }
}
