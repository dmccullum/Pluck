import AppKit
import AVFoundation
import SwiftUI

struct PlayerScreen: View {
    var model: VideoPlayerModel
    let player: AVPlayer

    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isSafeZonePopoverPresented = false
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
            .overlayPreferenceValue(ActionButtonAnchorKey.self) { anchors in
                if let flight = model.captureFlight {
                    let canvasSize = fittedCanvasSize(aspectRatio: model.videoAspectRatio, in: proxy.size)
                    let canvas = CGRect(
                        x: (proxy.size.width - canvasSize.width) / 2,
                        y: (proxy.size.height - canvasSize.height) / 2,
                        width: canvasSize.width,
                        height: canvasSize.height
                    )
                    let fallback = CGPoint(x: proxy.size.width - 48, y: proxy.size.height - 50)
                    CaptureFlightView(
                        flight: flight,
                        canvas: canvas,
                        target: anchors[flight.operation].map { proxy[$0] } ?? fallback
                    )
                    .id(flight.id)
                }
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
        .onChange(of: isSafeZonePopoverPresented) { _, isPresented in
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
            VStack(spacing: 1) {
                Text(model.videoURL?.lastPathComponent ?? "Pluck")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let videoDetails {
                    Text(videoDetails)
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
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

    private var videoDetails: String? {
        let size = model.videoDimensions
        guard size.width > 0, size.height > 0 else { return nil }
        let rate = model.frameRate
        let rateText = abs(rate - rate.rounded()) < 0.005
            ? String(format: "%.0f", rate)
            : String(format: "%.3f", rate).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
        return "\(Int(size.width))×\(Int(size.height)) · \(rateText) fps"
    }

    @ViewBuilder
    private func controlsLayer(compact: Bool) -> some View {
        if compact {
            VStack(spacing: 10) {
                Spacer()

                HStack {
                    if model.supportsSafeZone {
                        SafeZoneButton(model: model, isPopoverPresented: $isSafeZonePopoverPresented)
                    }
                    Spacer()
                    FrameActionButtons(model: model)
                }
                .padding(.horizontal, 18)

                PlaybackHUD(model: model)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 14)
            }
            .padding(.bottom, 16)
        } else {
            ZStack {
                VStack {
                    Spacer()
                    PlaybackHUD(model: model)
                        .frame(maxWidth: 480)
                        .padding(.horizontal, 76)
                        .padding(.bottom, 24)
                }

                VStack {
                    Spacer()
                    HStack {
                        if model.supportsSafeZone {
                            SafeZoneButton(model: model, isPopoverPresented: $isSafeZonePopoverPresented)
                        }
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
        guard !isSafeZonePopoverPresented, !model.isScrubbing, model.frameOperation == nil else { return }
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
        guard !isSafeZonePopoverPresented, !model.isScrubbing, model.frameOperation == nil else { return }
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
            MainActor.assumeIsolated {
                self?.isKHeld = false
            }
        }
    }

    isolated deinit {
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
    var model: VideoPlayerModel
    let player: AVPlayer

    var body: some View {
        GeometryReader { proxy in
            let canvasSize = fittedCanvasSize(aspectRatio: model.videoAspectRatio, in: proxy.size)

            ZStack {
                VideoSurface(player: player)

                if model.activeSafeZone != .off {
                    SafeZoneGuide(zone: model.activeSafeZone)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.activeSafeZone)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipped()
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

/// The largest size with the video's aspect ratio that fits in `availableSize`.
private func fittedCanvasSize(aspectRatio videoAspectRatio: Double, in availableSize: CGSize) -> CGSize {
    let aspectRatio = CGFloat(videoAspectRatio)
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

private struct SafeZoneButton: View {
    var model: VideoPlayerModel
    @Environment(\.playerControlsVisible) private var controlsVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var isPopoverPresented: Bool

    var body: some View {
        // The popover hangs off this stable container rather than the button, because
        // swapping button styles replaces the button and would dismiss the popover.
        Group {
            if model.safeZone != .off {
                button.buttonStyle(.glassProminent)
            } else {
                button.buttonStyle(.glass)
            }
        }
        .popover(isPresented: $isPopoverPresented, arrowEdge: .bottom) {
            SafeZonePopover(model: model)
        }
        .opacity(controlsVisible ? 1 : 0)
        .scaleEffect(controlsVisible || reduceMotion ? 1 : 0.92)
        .allowsHitTesting(controlsVisible)
    }

    private var button: some View {
        Button {
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                isPopoverPresented = false
                model.toggleSafeZone()
            } else {
                isPopoverPresented.toggle()
            }
        } label: {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 28, height: 28, alignment: .center)
                .accessibilityLabel("Safe Zone")
        }
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .help((model.safeZone == .off ? "Safe zone guides" : "Safe zone: \(model.safeZone.title)") + " · Command-click to turn \(model.safeZone == .off ? "on" : "off")")
        .accessibilityValue(model.safeZone == .off ? "Off" : model.safeZone.title)
    }
}

private struct SafeZonePopover: View {
    var model: VideoPlayerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Safe Zone")
                .font(.headline)

            Picker(
                "Safe Zone",
                selection: Binding(
                    get: { model.safeZone },
                    set: { model.setSafeZone($0) }
                )
            ) {
                ForEach(SafeZone.allCases) { zone in
                    Text(zone.title).tag(zone)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            Toggle(
                "Include in saved frames",
                isOn: Binding(
                    get: { model.includesSafeZoneInCaptures },
                    set: { model.setIncludesSafeZoneInCaptures($0) }
                )
            )
            .toggleStyle(.switch)
            .disabled(model.safeZone == .off)
            .padding(.top, 4)
        }
        .padding(16)
        .frame(width: 280)
    }
}

/// Dims everything outside a platform's safe area and outlines it.
/// Display only — it is never composited into captures.
private struct SafeZoneGuide: View {
    let zone: SafeZone

    var body: some View {
        Canvas { context, size in
            let points = zone.polygon.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
            guard !points.isEmpty else { return }
            var safeArea = Path()
            safeArea.addLines(points)
            safeArea.closeSubpath()

            var dimmed = Path(CGRect(origin: .zero, size: size))
            dimmed.addPath(safeArea)
            context.fill(dimmed, with: .color(.black.opacity(0.42)), style: FillStyle(eoFill: true))

            context.stroke(
                safeArea,
                with: .color(.white.opacity(0.9)),
                style: StrokeStyle(lineWidth: 1.5, lineJoin: .round, dash: [6, 4])
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
    var model: VideoPlayerModel
    @Environment(\.playerControlsVisible) private var controlsVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(PreferenceKey.timeDisplay) private var timeDisplayRaw = TimeDisplay.timecode.rawValue

    private var timeDisplay: TimeDisplay {
        TimeDisplay(rawValue: timeDisplayRaw) ?? .timecode
    }

    private var formatter: TimeFormatter {
        TimeFormatter(frameRate: model.frameRate, secondsPerFrame: model.secondsPerFrame, duration: model.duration)
    }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 14) {
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
                }
                .buttonStyle(HUDIconButtonStyle(diameter: 42))
                .keyboardShortcut(.space, modifiers: [])
                .help(model.isPlaying ? "Pause (Space)" : "Play (Space)")

                HUDButton(title: "Next Frame", systemImage: "forward.frame.fill") {
                    model.stepFrame(by: 1)
                }
                .keyboardShortcut(".", modifiers: [])
            }
            .overlay(alignment: .leading) {
                if model.shuttleRate < 0 {
                    speedLabel.offset(x: -30)
                }
            }
            .overlay(alignment: .trailing) {
                if model.shuttleRate > 1 {
                    speedLabel.offset(x: 30)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                timeButton(
                    formatter.string(model.currentTime, as: timeDisplay),
                    widest: formatter.widestString(as: timeDisplay),
                    isPrimary: true
                )

                // Lift the preview clear of the transport buttons above the track.
                Scrubber(model: model, previewLift: 78) { seconds in
                    formatter.string(seconds, as: timeDisplay)
                }
                .accessibilityLabel("Playback position")
                .accessibilityValue(playbackAccessibilityValue)

                timeButton(trailingTime, widest: trailingPrefix + formatter.widestString(as: timeDisplay), isPrimary: false)
            }
            .font(.system(size: 11.5, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 13)
        .glassEffect(
            .regular.tint(.black.opacity(0.22)).interactive(),
            in: .rect(cornerRadius: 22)
        )
        .foregroundStyle(.white)
        .opacity(controlsVisible ? 1 : 0)
        .offset(y: controlsVisible || reduceMotion ? 0 : 8)
        .allowsHitTesting(controlsVisible)
    }

    private var trailingPrefix: String {
        timeDisplay == .frames ? "/ " : "−"
    }

    private var trailingTime: String {
        switch timeDisplay {
        case .frames:
            trailingPrefix + formatter.string(model.duration, as: .frames)
        case .timecode, .clock:
            trailingPrefix + formatter.string(max(0, model.duration - model.currentTime), as: timeDisplay)
        }
    }

    /// `widest` is laid out invisibly underneath so the label's width never changes.
    private func timeButton(_ text: String, widest: String, isPrimary: Bool) -> some View {
        Button {
            timeDisplayRaw = timeDisplay.next.rawValue
        } label: {
            ZStack(alignment: isPrimary ? .leading : .trailing) {
                Text(widest).hidden()
                Text(text)
                    .foregroundStyle(isPrimary ? .white : .white.opacity(0.6))
            }
            .monospacedDigit()
            .fixedSize()
        }
        .buttonStyle(.plain)
        .help("Showing \(timeDisplay.title.lowercased()) · Click to show \(timeDisplay.next.title.lowercased())")
    }

    private var playbackAccessibilityValue: String {
        let position = formatter.string(model.currentTime, as: .clock)
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
    var model: VideoPlayerModel
    @Environment(\.playerControlsVisible) private var controlsVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                FrameActionButton(model: model, operation: .copy)
                FrameActionButton(model: model, operation: .save)
            }
        }
        .opacity(controlsVisible ? 1 : 0)
        .scaleEffect(controlsVisible || reduceMotion ? 1 : 0.92)
        .allowsHitTesting(controlsVisible)
    }
}

private struct FrameActionButton: View {
    var model: VideoPlayerModel
    let operation: FrameOperation

    private var isWorking: Bool {
        operation == .copy ? model.isCopyingFrame : model.isSavingFrame
    }

    private var title: String {
        operation == .copy ? "Copy Frame" : "Save Frame"
    }

    private var isDone: Bool {
        model.completedOperation == operation && !isWorking
    }

    private var symbolName: String {
        if isWorking { return "hourglass" }
        if isDone { return "checkmark" }
        return operation == .copy ? "doc.on.doc" : "camera.shutter.button.fill"
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
            Image(systemName: symbolName)
                .font(.system(size: 17, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .offset(x: operation == .copy && !isDone ? 2 : 0, y: operation == .copy && !isDone ? -1 : 0)
                .frame(width: 28, height: 28)
                .accessibilityLabel(isWorking ? "\(operation == .copy ? "Copying" : "Saving") Frame" : title)
        }
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .disabled(model.isCapturing)
        .anchorPreference(key: ActionButtonAnchorKey.self, value: .center) { [operation: $0] }
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
                .font(.system(size: 17, weight: .semibold))
        }
        .buttonStyle(HUDIconButtonStyle(diameter: 34))
        .help(title + (title == "Previous Frame" ? " (←, comma, or K+J)" : " (→, period, or K+L)"))
    }
}

private struct ActionButtonAnchorKey: SwiftUI.PreferenceKey {
    static let defaultValue: [FrameOperation: Anchor<CGPoint>] = [:]

    static func reduce(value: inout [FrameOperation: Anchor<CGPoint>], nextValue: () -> [FrameOperation: Anchor<CGPoint>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// The capture moment: a quick flash, then the frame shrinks, tilts like the
/// icon's plucked frame, and drops into the button that took it.
private struct CaptureFlightView: View {
    let flight: CaptureFlight
    let canvas: CGRect
    let target: CGPoint

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash = 0.5
    @State private var launched = false
    @State private var landed = false

    var body: some View {
        let endScale = 58 / max(canvas.width, canvas.height, 1)
        let cornerRadius = launched ? 7 / endScale : 0
        let border = launched ? 2.5 / endScale : 0

        ZStack {
            Color.white
                .opacity(flash)
                .frame(width: canvas.width, height: canvas.height)
                .position(x: canvas.midX, y: canvas.midY)

            Image(nsImage: flight.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: canvas.width, height: canvas.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white, lineWidth: border)
                }
                .shadow(color: .black.opacity(launched ? 0.45 : 0), radius: launched ? 8 / endScale : 0, y: launched ? 4 / endScale : 0)
                .scaleEffect(launched ? endScale : 1)
                .rotationEffect(.degrees(launched ? 7 : 0))
                .position(launched ? target : CGPoint(x: canvas.midX, y: canvas.midY))
                .opacity(landed ? 0 : 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                flash = 0
            }
            // With Reduce Motion, keep the flash and skip the flight into the button.
            guard !reduceMotion else {
                landed = true
                return
            }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.86).delay(0.06)) {
                launched = true
            }
            withAnimation(.easeIn(duration: 0.16).delay(0.5)) {
                landed = true
            }
        }
    }
}
