import AppKit
import AVFoundation
import SwiftUI

struct PlayerScreen: View {
    @ObservedObject var model: VideoPlayerModel
    let player: AVPlayer

    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isOverlayPopoverPresented = false
    @State private var isPointerInside = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VideoCanvas(model: model, player: player)
                PointerTrackingView(
                    onActivity: {
                        isPointerInside = true
                        showControls(andScheduleHide: true)
                    },
                    onExit: {
                        isPointerInside = false
                        hideControlsNow()
                    },
                    onFrameStep: { count in
                        model.stepFrame(by: count)
                    }
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                controlsLayer(compact: proxy.size.width < 760)
                topChrome
            }
        }
        .background(.black)
        .ignoresSafeArea(edges: .top)
        .animation(.easeOut(duration: 0.22), value: model.controlsVisible)
        .onChange(of: model.isPlaying) { _, _ in
            showControls(andScheduleHide: true)
        }
        .onChange(of: model.isScrubbing) { _, isScrubbing in
            if isScrubbing {
                showControls(andScheduleHide: false)
            } else {
                hideControlsAfterInteraction()
            }
        }
        .onChange(of: isOverlayPopoverPresented) { _, isPresented in
            if isPresented {
                showControls(andScheduleHide: false)
            } else {
                hideControlsAfterInteraction()
            }
        }
        .onChange(of: model.frameOperation) { _, operation in
            if operation == nil {
                hideControlsAfterInteraction()
            } else {
                showControls(andScheduleHide: false)
            }
        }
        .onAppear {
            showControls(andScheduleHide: true)
        }
        .onDisappear {
            hideControlsTask?.cancel()
            model.setControlsVisible(true)
        }
        .environment(\.playerControlsVisible, model.controlsVisible)
    }

    private var topChrome: some View {
        VStack {
            Text(model.videoURL?.lastPathComponent ?? "Shotgrabber")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 90)
                .padding(.top, 7)
                .padding(.bottom, 38)
                .background {
                    LinearGradient(
                        colors: [.black.opacity(0.48), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            Spacer()
        }
        .opacity(model.controlsVisible ? 1 : 0)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func controlsLayer(compact: Bool) -> some View {
        if compact {
            VStack(spacing: 10) {
                Spacer()

                HStack {
                    OverlayButton(model: model, isPopoverPresented: $isOverlayPopoverPresented)
                    Spacer()
                    FrameActionButtons(model: model)
                }
                .padding(.horizontal, 18)

                PlaybackHUD(model: model)
                    .frame(maxWidth: 500)
                    .padding(.horizontal, 14)
            }
            .padding(.bottom, 16)
        } else {
            ZStack {
                VStack {
                    Spacer()
                    PlaybackHUD(model: model)
                        .frame(maxWidth: 440)
                        .padding(.horizontal, 76)
                        .padding(.bottom, 24)
                }

                VStack {
                    Spacer()
                    HStack {
                        OverlayButton(model: model, isPopoverPresented: $isOverlayPopoverPresented)
                        Spacer()
                    }
                    .padding(.leading, 24)
                    .padding(.bottom, 28)
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FrameActionButtons(model: model)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 28)
                }
            }
        }
    }

    private func showControls(andScheduleHide shouldHide: Bool) {
        hideControlsTask?.cancel()
        model.setControlsVisible(true)
        if shouldHide {
            scheduleControlsHide()
        }
    }

    private func scheduleControlsHide() {
        guard !isOverlayPopoverPresented, !model.isScrubbing, model.frameOperation == nil else { return }
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                model.setControlsVisible(false)
            }
        }
    }

    private func hideControlsAfterInteraction() {
        if isPointerInside {
            scheduleControlsHide()
        } else {
            hideControlsNow()
        }
    }

    private func hideControlsNow() {
        guard !isOverlayPopoverPresented, !model.isScrubbing, model.frameOperation == nil else { return }
        hideControlsTask?.cancel()
        model.setControlsVisible(false)
    }
}

private struct PointerTrackingView: NSViewRepresentable {
    let onActivity: () -> Void
    let onExit: () -> Void
    let onFrameStep: (Int) -> Void

    func makeNSView(context: Context) -> PointerTrackingNSView {
        let view = PointerTrackingNSView()
        view.onActivity = onActivity
        view.onExit = onExit
        view.onFrameStep = onFrameStep
        return view
    }

    func updateNSView(_ nsView: PointerTrackingNSView, context: Context) {
        nsView.onActivity = onActivity
        nsView.onExit = onExit
        nsView.onFrameStep = onFrameStep
    }
}

private final class PointerTrackingNSView: NSView {
    var onActivity: (() -> Void)?
    var onExit: (() -> Void)?
    var onFrameStep: ((Int) -> Void)?
    private var pointerArea: NSTrackingArea?
    private var eventMonitor: Any?
    private var keyboardMonitor: Any?
    private var windowResignObserver: Any?
    private var isKHeld = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
            self.keyboardMonitor = nil
        }
        if let windowResignObserver {
            NotificationCenter.default.removeObserver(windowResignObserver)
            self.windowResignObserver = nil
        }
        isKHeld = false
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .rightMouseDown, .rightMouseDragged]
        ) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            let location = self.convert(event.locationInWindow, from: nil)
            if self.bounds.contains(location) {
                self.onActivity?()
            } else {
                self.onExit?()
            }
            return event
        }
        // SwiftUI shortcuts cannot express holding K while tapping J or L.
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self, weak window] event in
            guard let self, let window, event.window === window else { return event }
            if event.keyCode == 40, event.type == .keyUp {
                self.isKHeld = false
                return event
            }
            guard event.type == .keyDown,
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                  !(window.firstResponder is NSTextView) else { return event }

            if event.keyCode == 40 {
                self.isKHeld = true
                return event
            }
            let frameStep = event.keyCode == 38 ? -1 : (event.keyCode == 37 ? 1 : 0)
            guard frameStep != 0 else { return event }
            if event.isARepeat { return nil }
            if self.isKHeld {
                self.onFrameStep?(frameStep)
                return nil
            }
            return event
        }
        windowResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.isKHeld = false
        }
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        if let keyboardMonitor {
            NSEvent.removeMonitor(keyboardMonitor)
        }
        if let windowResignObserver {
            NotificationCenter.default.removeObserver(windowResignObserver)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerArea {
            removeTrackingArea(pointerArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        pointerArea = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func mouseEntered(with event: NSEvent) { onActivity?() }
    override func mouseMoved(with event: NSEvent) { onActivity?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

private struct VideoCanvas: View {
    @ObservedObject var model: VideoPlayerModel
    let player: AVPlayer

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = fittedCanvasSize(in: proxy.size)

            ZStack {
                VideoSurface(player: player)

                if model.isOverlayEnabled, let overlayImage = model.overlayImage {
                    Image(nsImage: overlayImage)
                        .resizable()
                        .aspectRatio(contentMode: model.overlaySizing == .fit ? .fit : .fill)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipped()
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private func fittedCanvasSize(in availableSize: CGSize) -> CGSize {
        let aspectRatio = CGFloat(model.videoAspectRatio)
        guard aspectRatio.isFinite,
              aspectRatio > 0,
              availableSize.width > 0,
              availableSize.height > 0 else {
            return availableSize
        }

        if availableSize.width / availableSize.height > aspectRatio {
            return CGSize(
                width: availableSize.height * aspectRatio,
                height: availableSize.height
            )
        }
        return CGSize(
            width: availableSize.width,
            height: availableSize.width / aspectRatio
        )
    }
}

private struct OverlayButton: View {
    @ObservedObject var model: VideoPlayerModel
    @Environment(\.playerControlsVisible) private var controlsVisible
    @Binding var isPopoverPresented: Bool

    @ViewBuilder
    var body: some View {
        if model.hasOverlay && model.isOverlayEnabled {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private var button: some View {
        Button {
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                if model.hasOverlay {
                    isPopoverPresented = false
                    model.setOverlayEnabled(!model.isOverlayEnabled)
                } else {
                    model.presentOverlayPanel()
                }
            } else {
                isPopoverPresented.toggle()
            }
        } label: {
            Image(systemName: "plus.viewfinder")
                .font(.system(size: 17, weight: .semibold))
                .offset(x: 0.5, y: -0.5)
                .frame(width: 28, height: 28, alignment: .center)
                .accessibilityLabel("PNG Overlay")
        }
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .help(model.hasOverlay ? "PNG Overlay: \(model.overlayName ?? "") · Command-click to turn \(model.isOverlayEnabled ? "off" : "on")" : "Add PNG Overlay")
        .accessibilityValue(model.hasOverlay ? (model.isOverlayEnabled ? "On" : "Off") : "No overlay")
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            OverlayPopover(model: model, isPresented: $isPopoverPresented)
        }
        .opacity(controlsVisible ? 1 : 0)
        .scaleEffect(controlsVisible ? 1 : 0.92)
        .allowsHitTesting(controlsVisible)
    }
}

private struct OverlayPopover: View {
    @ObservedObject var model: VideoPlayerModel
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                overlayPreview

                VStack(alignment: .leading, spacing: 3) {
                    Text("PNG Overlay")
                        .font(.headline)
                    Text(model.overlayName ?? "No overlay selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if model.hasOverlay {
                Toggle(
                    "Show Overlay",
                    isOn: Binding(
                        get: { model.isOverlayEnabled },
                        set: { model.setOverlayEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

                HStack {
                    Text("Sizing")
                    Spacer()
                    Picker(
                        "Sizing",
                        selection: Binding(
                            get: { model.overlaySizing },
                            set: { model.setOverlaySizing($0) }
                        )
                    ) {
                        ForEach(OverlaySizing.allCases) { sizing in
                            Text(sizing.title).tag(sizing)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 116)
                }

                Divider()

                HStack {
                    Button("Replace…") {
                        isPresented = false
                        model.presentOverlayPanel()
                    }

                    Spacer()

                    Button("Remove", role: .destructive) {
                        model.removeOverlay()
                        isPresented = false
                    }
                }
            } else {
                Button("Choose PNG…") {
                    isPresented = false
                    model.presentOverlayPanel()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    @ViewBuilder
    private var overlayPreview: some View {
        if let image = model.overlayImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct PlayerControlsVisibilityKey: EnvironmentKey {
    static let defaultValue = true
}

private extension EnvironmentValues {
    var playerControlsVisible: Bool {
        get { self[PlayerControlsVisibilityKey.self] }
        set { self[PlayerControlsVisibilityKey.self] = newValue }
    }
}

private struct PlaybackHUD: View {
    @ObservedObject var model: VideoPlayerModel
    @Environment(\.playerControlsVisible) private var controlsVisible

    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 22) {
                HUDButton(title: "Previous Frame", systemImage: "backward.frame.fill") {
                    model.stepFrame(by: -1)
                }
                .keyboardShortcut(",", modifiers: [])

                Button {
                    model.togglePlayback()
                } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 34, height: 30)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.space, modifiers: [])
                .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")

                HUDButton(title: "Next Frame", systemImage: "forward.frame.fill") {
                    model.stepFrame(by: 1)
                }
                .keyboardShortcut(".", modifiers: [])
            }
            .overlay(alignment: .leading) {
                if model.shuttleRate < 0 {
                    speedLabel.offset(x: -25)
                }
            }
            .overlay(alignment: .trailing) {
                if model.shuttleRate > 1 {
                    speedLabel.offset(x: 25)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 10) {
                Text(timecode(model.currentTime))
                    .monospacedDigit()

                Slider(
                    value: Binding(
                        get: { model.currentTime },
                        set: { model.scrub(to: $0) }
                    ),
                    in: 0...max(model.duration, 0.001),
                    onEditingChanged: { editing in
                        if editing {
                            model.beginScrubbing()
                        } else {
                            model.endScrubbing()
                        }
                    }
                )
                .controlSize(.small)
                .accessibilityLabel("Playback position")
                .accessibilityValue(playbackAccessibilityValue)
                .help("Scrub to choose a frame")

                Text("−\(timecode(max(0, model.duration - model.currentTime)))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .glassEffect(
            .regular.tint(.black.opacity(0.22)),
            in: .rect(cornerRadius: 22)
        )
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
        .opacity(controlsVisible ? 1 : 0)
        .offset(y: controlsVisible ? 0 : 8)
        .allowsHitTesting(controlsVisible)
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "00:00" }
        let wholeSeconds = max(0, Int(seconds))
        let hours = wholeSeconds / 3600
        let minutes = (wholeSeconds / 60) % 60
        let secs = wholeSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    private var playbackAccessibilityValue: String {
        let position = timecode(model.currentTime)
        guard model.shuttleRate != 0, model.shuttleRate != 1 else { return position }
        let direction = model.shuttleRate < 0 ? "reverse" : "forward"
        return "\(position), \(direction) \(Int(abs(model.shuttleRate))) times speed"
    }

    private var speedLabel: some View {
        Text("\(Int(abs(model.shuttleRate)))×")
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.9))
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct FrameActionButtons: View {
    @ObservedObject var model: VideoPlayerModel
    @Environment(\.playerControlsVisible) private var controlsVisible

    var body: some View {
        HStack(spacing: 8) {
            FrameActionButton(model: model, operation: .copy)
            FrameActionButton(model: model, operation: .save)
        }
        .opacity(controlsVisible ? 1 : 0)
        .scaleEffect(controlsVisible ? 1 : 0.92)
        .allowsHitTesting(controlsVisible)
    }
}

private struct FrameActionButton: View {
    @ObservedObject var model: VideoPlayerModel
    let operation: FrameOperation

    private var isWorking: Bool {
        operation == .copy ? model.isCopyingFrame : model.isSavingFrame
    }

    private var title: String {
        operation == .copy ? "Copy Frame" : "Save Frame"
    }

    @ViewBuilder
    var body: some View {
        if operation == .copy {
            button
                .buttonStyle(.glass)
                .keyboardShortcut("c", modifiers: .command)
        } else {
            button.buttonStyle(.glassProminent)
        }
    }

    private var button: some View {
        Button {
            if operation == .copy {
                model.copyCurrentFrame()
            } else {
                model.captureCurrentFrame()
            }
        } label: {
            Image(systemName: isWorking ? "hourglass" : (operation == .copy ? "doc.on.doc" : "camera.shutter.button.fill"))
                .font(.system(size: 17, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .offset(x: operation == .copy ? 2 : 0, y: operation == .copy ? -1 : 0)
                .frame(width: 28, height: 28)
                .accessibilityLabel(isWorking ? "\(operation == .copy ? "Copying" : "Saving") Frame" : title)
        }
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .disabled(model.isCapturing)
        .help("\(title) (Command-\(operation == .copy ? "C" : "S"))")
    }
}

private struct HUDButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 25, height: 25)
        }
        .buttonStyle(.plain)
        .help(title + (title == "Previous Frame" ? " (←, comma, or K+J)" : " (→, period, or K+L)"))
    }
}
