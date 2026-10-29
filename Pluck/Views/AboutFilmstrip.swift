import AppKit
import DMKit
import SwiftUI

/// The About window's signature: eight frames of a sunset on a strip of film, a playhead
/// and the HUD's timecode. Moving the pointer over the strip (or dragging) scrubs frame by
/// frame, ← and → step, and a click plucks the current frame: a shutter flash, then the
/// frame lifts out as a photo and drops onto a stack of up to four. Clicking the stack clears it.
/// Return or Space plucks and Delete clears too.
struct AboutFilmstrip: View {
    @State private var reel = FilmstripReel()
    @State private var keys = FilmstripKeys()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var increasedContrast: Bool { contrast == .increased }

    var body: some View {
        ZStack(alignment: .topLeading) {
            strip
            scrubber
            stackBase
            bottomRow
            cards
        }
        .frame(width: Layout.width, height: Layout.height, alignment: .topLeading)
        .background(FilmstripWindowReader { keys.watch($0, reel: reel) })
        // The window can close and reopen around the same view, so take the keys back on appear.
        .onAppear { keys.watch(keys.window, reel: reel) }
        .onDisappear {
            keys.stop()
            reel.cancel()
        }
    }

    // MARK: Strip

    private var strip: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Brand.film)
                .frame(width: Layout.width, height: Layout.stripHeight)
                .position(x: Layout.width / 2, y: Layout.stripHeight / 2)

            Sprockets()
                .frame(width: Layout.width, height: Layout.stripHeight)
                .position(x: Layout.width / 2, y: Layout.stripHeight / 2)

            ForEach(0..<FilmstripReel.frameCount, id: \.self) { index in
                cell(index)
                    .frame(width: Layout.cellSize.width, height: Layout.cellSize.height)
                    .position(Layout.cellCenter(index))
            }

            // The frame under the playhead.
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .strokeBorder(.white, lineWidth: increasedContrast ? 2.5 : 2)
                .frame(width: Layout.cellSize.width + 5, height: Layout.cellSize.height + 5)
                .position(Layout.cellCenter(reel.frame))
                .dmAnimation(.snappy, value: reel.frame)

            // The shutter flash, over the frame that was just plucked.
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(.white)
                .frame(width: Layout.cellSize.width + 4, height: Layout.cellSize.height + 4)
                .keyframeAnimator(initialValue: 0.0, trigger: reel.flashCount) { content, opacity in
                    content.opacity(opacity)
                } keyframes: { _ in
                    LinearKeyframe(reduceMotion ? 0.55 : 0.95, duration: 0.03)
                    CubicKeyframe(0, duration: reduceMotion ? 0.3 : 0.38)
                }
                .position(Layout.cellCenter(reel.flashFrame))
        }
        .allowsHitTesting(false)
        .overlay(alignment: .topLeading) { stripHitArea }
    }

    private func cell(_ index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2.5, style: .continuous)
        return ZStack {
            if reel.isInFlight(index) {
                // The empty slot the frame was plucked from, as in the app icon.
                shape.strokeBorder(.white.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
                    .transition(.opacity)
            } else {
                SunsetFrame(t: FilmstripReel.sceneTime(index))
                    .clipShape(shape)
                    .opacity(index == reel.frame ? 1 : (increasedContrast ? 0.9 : 0.74))
                    .transition(.opacity)
            }
        }
        .dmAnimation(.smooth, value: reel.isInFlight(index))
        .dmAnimation(.snappy, value: reel.frame)
    }

    /// Hover or drag scrubs; a click without a drag plucks.
    private var stripHitArea: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: Layout.width, height: Layout.scrubberY + 8)
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    reel.seek(to: Layout.frame(at: location.x))
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in reel.seek(to: Layout.frame(at: value.location.x)) }
                    .onEnded { value in
                        if hypot(value.translation.width, value.translation.height) < 4 {
                            reel.pluck()
                        }
                    }
            )
            .help("Move over the film to scrub · Click to pluck the frame · ← → step one frame")
            .accessibilityElement()
            .accessibilityLabel("Filmstrip of a sunset")
            .accessibilityValue("Frame \(reel.frame + 1) of \(FilmstripReel.frameCount), \(reel.timecode)")
            .accessibilityHint("Plucks the frame onto the stack")
            .accessibilityAddTraits(.isButton)
            .accessibilityAdjustableAction { direction in
                reel.step(direction == .increment ? 1 : -1)
            }
            .accessibilityAction { reel.pluck() }
            .accessibilityAction(named: "Pluck Frame") { reel.pluck() }
    }

    /// The HUD scrubber in miniature: accent fill up to a white knob over the current frame.
    private var scrubber: some View {
        let knobX = Layout.cellCenter(reel.frame).x
        let trackWidth = Layout.width - Layout.inset * 2
        return ZStack(alignment: .leading) {
            Capsule()
                .fill(.primary.opacity(increasedContrast ? 0.3 : 0.14))
                .frame(width: trackWidth, height: 4)
            Capsule()
                .fill(Color.accentColor)
                .frame(width: knobX - Layout.inset, height: 4)
            Circle()
                .fill(.white)
                .overlay(Circle().strokeBorder(.black.opacity(increasedContrast ? 0.4 : 0.12), lineWidth: 0.5))
                .frame(width: 11, height: 11)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .offset(x: knobX - Layout.inset - 5.5)
        }
        .frame(width: trackWidth, height: 12, alignment: .leading)
        .position(x: Layout.width / 2, y: Layout.scrubberY)
        .dmAnimation(.snappy, value: reel.frame)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Transport and stack

    private var bottomRow: some View {
        HStack {
            transport
            Spacer(minLength: 0)
        }
        .frame(width: Layout.width, height: Layout.rowHeight)
        .position(x: Layout.width / 2, y: Layout.stackCenter.y)
    }

    /// The HUD's step buttons around its timecode, on the film's stock.
    private var transport: some View {
        HStack(spacing: 2) {
            Button { reel.step(-1) } label: {
                Image(systemName: "backward.frame.fill")
            }
            .buttonStyle(HUDIconButtonStyle(diameter: 26))
            .help("Previous Frame (←)")
            .accessibilityLabel("Previous Frame")

            Text(reel.timecode)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(reel.frame)))
                .dmAnimation(.snappy, value: reel.frame)
                .padding(.horizontal, 3)
                .accessibilityHidden(true)

            Button { reel.step(1) } label: {
                Image(systemName: "forward.frame.fill")
            }
            .buttonStyle(HUDIconButtonStyle(diameter: 26))
            .help("Next Frame (→)")
            .accessibilityLabel("Next Frame")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 3)
        .frame(height: 32)
        .background(Capsule().fill(Brand.film))
        .overlay {
            if increasedContrast {
                Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1)
            }
        }
    }

    /// The dashed slot the stack sits in, and the click that clears it.
    private var stackBase: some View {
        let isEmpty = reel.stackedCount == 0
        return RoundedRectangle(cornerRadius: 5, style: .continuous)
            .strokeBorder(.secondary.opacity(increasedContrast ? 0.9 : 0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
            .frame(width: Layout.cardSize.width, height: Layout.cardSize.height)
            .opacity(isEmpty ? 1 : 0)
            .dmAnimation(.smooth, value: isEmpty)
            .frame(width: Layout.cardSize.width + 28, height: Layout.rowHeight)
            .contentShape(Rectangle())
            .onTapGesture { reel.clear() }
            .help(isEmpty ? "Plucked frames land here" : "Click to clear the stack")
            .position(Layout.stackCenter)
            .accessibilityElement()
            .accessibilityLabel("Plucked frames")
            .accessibilityValue(isEmpty ? "None" : "\(reel.stackedCount)")
            .accessibilityAction(named: "Clear") { reel.clear() }
    }

    /// Every plucked photo: sitting over its slot, lifted out, or on the stack.
    private var cards: some View {
        ForEach(reel.photos) { photo in
            let placement = placement(of: photo)
            PhotoCard(t: FilmstripReel.sceneTime(photo.frame), outlined: increasedContrast)
                .frame(width: placement.size.width, height: placement.size.height)
                .rotationEffect(.degrees(placement.rotation))
                .shadow(color: .black.opacity(placement.shadow), radius: placement.shadow * 22, y: placement.shadow * 10)
                .position(placement.center)
                .transition(DMMotion.transition(.opacity.combined(with: .offset(y: 10)), reduceMotion: reduceMotion))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func placement(of photo: FilmstripReel.Photo) -> (center: CGPoint, size: CGSize, rotation: Double, shadow: Double) {
        let slot = Layout.cellCenter(photo.frame)
        switch photo.phase {
        case .slot:
            return (slot, Layout.cellSize, 0, 0)
        case .lifted:
            let size = CGSize(width: Layout.cellSize.width * 1.35, height: Layout.cellSize.height * 1.35)
            return (CGPoint(x: slot.x, y: slot.y - 8), size, photo.tilt * 0.3, 0.32)
        case .stacked:
            let depth = CGFloat(reel.stackIndex(of: photo))
            let center = CGPoint(x: Layout.stackCenter.x - 4 + depth * 3, y: Layout.stackCenter.y + 2 - depth * 2)
            return (center, Layout.cardSize, photo.tilt, 0.2)
        }
    }
}

// MARK: - Model

/// The strip's playhead and the stack of plucked frames.
@Observable
final class FilmstripReel {
    static let frameCount = 8
    static let stackLimit = 4
    private static let tilts = [-7.0, 5, -3, 8]
    private static let formatter = TimeFormatter(frameRate: 24, secondsPerFrame: 1.0 / 24, duration: Double(frameCount) / 24)

    struct Photo: Identifiable {
        enum Phase { case slot, lifted, stacked }
        let id = UUID()
        let frame: Int
        let tilt: Double
        var phase: Phase
    }

    private(set) var frame = 3
    private(set) var photos: [Photo] = []
    /// The frame the shutter flash plays over, and a count that fires it.
    private(set) var flashFrame = 3
    private(set) var flashCount = 0
    private var plucks = 0
    private var flights: [UUID: Task<Void, Never>] = [:]

    /// Where the sun is in a frame, from 0 (high) to 1 (set).
    static func sceneTime(_ frame: Int) -> Double {
        Double(frame) / Double(frameCount - 1)
    }

    /// The frame as the HUD shows it in Timecode, at 24 fps.
    var timecode: String {
        Self.formatter.string(Double(frame) / 24, as: .timecode)
    }

    var stackedCount: Int { photos.count { $0.phase == .stacked } }

    func stackIndex(of photo: Photo) -> Int {
        photos.prefix { $0.id != photo.id }.count { $0.phase == .stacked }
    }

    func isInFlight(_ frame: Int) -> Bool {
        photos.contains { $0.frame == frame && $0.phase != .stacked }
    }

    /// Moves the playhead, with a detent tick on each new frame.
    func seek(to target: Int) {
        let clamped = min(Self.frameCount - 1, max(0, target))
        guard clamped != frame else { return }
        frame = clamped
        tick()
    }

    func step(_ direction: Int) {
        seek(to: frame + direction)
    }

    /// Flashes the current frame, lifts it out of the strip and drops it on the stack.
    /// Under Reduce Motion the photo fades in on the stack instead of travelling.
    func pluck() {
        flashFrame = frame
        flashCount += 1
        let photo = Photo(frame: frame, tilt: Self.tilts[plucks % Self.tilts.count], phase: DMMotion.reduceMotion ? .stacked : .slot)
        plucks += 1

        if DMMotion.reduceMotion {
            withDMAnimation(.smooth) {
                photos.append(photo)
                trimStack()
            }
            tick()
            return
        }

        // In its slot first, with no animation, so the lift starts from the strip.
        photos.append(photo)
        let id = photo.id
        flights[id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let self else { return }
            withDMAnimation(.snappy) { self.setPhase(.lifted, of: id) }
            try? await Task.sleep(for: .milliseconds(170))
            guard !Task.isCancelled else { return }
            withDMAnimation(.spring) {
                self.setPhase(.stacked, of: id)
                self.trimStack()
            }
            try? await Task.sleep(for: .milliseconds(260))
            guard !Task.isCancelled else { return }
            self.tick()
            self.flights[id] = nil
        }
    }

    /// Clears the photos on the stack; ones still in the air keep landing.
    func clear() {
        guard stackedCount > 0 else { return }
        withDMAnimation(.smooth) {
            photos.removeAll { $0.phase == .stacked }
        }
    }

    func cancel() {
        flights.values.forEach { $0.cancel() }
        flights.removeAll()
        photos.removeAll()
    }

    private func setPhase(_ phase: Photo.Phase, of id: UUID) {
        guard let index = photos.firstIndex(where: { $0.id == id }) else { return }
        photos[index].phase = phase
    }

    /// Drops the oldest photos once the stack holds more than four.
    private func trimStack() {
        while stackedCount > Self.stackLimit, let oldest = photos.firstIndex(where: { $0.phase == .stacked }) {
            photos.remove(at: oldest)
        }
    }

    private func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

// MARK: - Layout

private enum Layout {
    static let width: CGFloat = 336
    static let inset: CGFloat = 6
    static let gap: CGFloat = 4
    static let sprocketBand: CGFloat = 9
    static let cellSize = CGSize(
        width: (width - inset * 2 - gap * CGFloat(FilmstripReel.frameCount - 1)) / CGFloat(FilmstripReel.frameCount),
        height: 26
    )
    static let stripHeight = cellSize.height + sprocketBand * 2
    static let scrubberY = stripHeight + 11
    static let rowTop = scrubberY + 14
    static let rowHeight: CGFloat = 62
    static let height = rowTop + rowHeight
    static let cardSize = CGSize(width: 62, height: 44)
    static let stackCenter = CGPoint(x: width - 46, y: rowTop + rowHeight / 2)

    static func cellCenter(_ index: Int) -> CGPoint {
        CGPoint(
            x: inset + cellSize.width / 2 + CGFloat(index) * (cellSize.width + gap),
            y: sprocketBand + cellSize.height / 2
        )
    }

    static func frame(at x: CGFloat) -> Int {
        Int(((x - inset + gap / 2) / (cellSize.width + gap)).rounded(.down))
    }
}

// MARK: - Drawing

/// The film's perforations along both edges.
private struct Sprockets: View {
    var body: some View {
        Canvas { context, size in
            var holes = Path()
            for x in stride(from: CGFloat(6), through: size.width - 9, by: 9) {
                holes.addRoundedRect(in: CGRect(x: x, y: 2.6, width: 4, height: 3.8), cornerSize: CGSize(width: 1, height: 1))
                holes.addRoundedRect(in: CGRect(x: x, y: size.height - 6.4, width: 4, height: 3.8), cornerSize: CGSize(width: 1, height: 1))
            }
            context.fill(holes, with: .color(.white.opacity(0.3)))
        }
    }
}

/// One frame of the scene: the sun dropping behind the icon's mountains as the sky turns
/// from blue to sunset. `t` runs from 0 (afternoon) to 1 (just after sunset).
struct SunsetFrame: View {
    let t: Double

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let top = Brand.skyBottom.mix(with: Brand.mountainTop, by: t)
            let horizon = Brand.skyTop
                .mix(with: Brand.sunsetTop, by: min(1, t * 1.5))
                .mix(with: Brand.sunsetBottom, by: max(0, t - 0.45) * 1.5)
            context.fill(
                Path(rect),
                with: .linearGradient(Gradient(colors: [top, horizon]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height))
            )

            let radius = size.height * 0.16
            let sun = CGPoint(x: size.width * (0.26 + 0.3 * t), y: size.height * (0.2 + 0.5 * t))
            let sunColor = Color(.displayP3, red: 1, green: 0.99, blue: 0.9).mix(with: Brand.sunsetTop, by: t * 0.8)
            let glow = radius * 2.2
            context.fill(
                Path(ellipseIn: CGRect(x: sun.x - glow, y: sun.y - glow, width: glow * 2, height: glow * 2)),
                with: .radialGradient(
                    Gradient(colors: [sunColor.opacity(0.2 + 0.3 * t), sunColor.opacity(0)]),
                    center: sun, startRadius: radius, endRadius: glow
                )
            )
            context.fill(Path(ellipseIn: CGRect(x: sun.x - radius, y: sun.y - radius, width: radius * 2, height: radius * 2)), with: .color(sunColor))

            context.fill(
                MountainShape().path(in: rect),
                with: .linearGradient(
                    Gradient(colors: [Brand.mountainTop, Brand.mountainBottom]),
                    startPoint: CGPoint(x: 0, y: size.height * 0.3),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            // Dusk settles over the last frames.
            context.fill(Path(rect), with: .color(Brand.mountainBottom.opacity(0.28 * t * t)))
        }
    }
}

/// A plucked frame as a print: the scene inside a white border.
private struct PhotoCard: View {
    let t: Double
    var outlined = false

    var body: some View {
        GeometryReader { proxy in
            let inset = proxy.size.width * 0.06
            let radius = proxy.size.width * 0.08
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.white)
                SunsetFrame(t: t)
                    .clipShape(RoundedRectangle(cornerRadius: max(1, radius - inset), style: .continuous))
                    .padding(inset)
                if outlined {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.black.opacity(0.45), lineWidth: 1)
                }
            }
        }
    }
}

// MARK: - Keys

/// The About window's keys. A monitor rather than focus, so the strip needs no focus ring.
private final class FilmstripKeys {
    private(set) weak var window: NSWindow?
    private var monitor: Any?

    func watch(_ window: NSWindow?, reel: FilmstripReel) {
        stop()
        self.window = window
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let window = self?.window, event.window === window, window.isKeyWindow,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 123: reel.step(-1)          // ←
            case 124: reel.step(1)           // →
            case 36, 49, 76: reel.pluck()    // Return, Space, Enter
            case 51, 117: reel.clear()       // Delete, Forward Delete
            default: return event
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    isolated deinit { stop() }
}

/// Reports the window the signature is in, without taking any clicks.
private struct FilmstripWindowReader: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: ReaderView, context: Context) {
        nsView.onWindow = onWindow
    }

    final class ReaderView: NSView {
        var onWindow: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindow?(window)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

#Preview("About signature") {
    AboutFilmstrip()
        .padding(32)
        .frame(width: 400)
}
