import SwiftUI

/// Colors lifted from the app icon so the UI and the icon read as one thing.
enum Brand {
    static let skyTop = p3(96, 200, 255)
    static let skyBottom = p3(24, 80, 220)
    static let frameTop = p3(255, 220, 150)
    static let frameBottom = p3(250, 172, 104)
    static let sunsetTop = p3(255, 196, 64)
    static let sunsetBottom = p3(255, 70, 96)
    static let mountainTop = p3(96, 60, 236)
    static let mountainBottom = p3(36, 18, 140)
    static let film = p3(16, 20, 36)

    static let sunset = LinearGradient(colors: [sunsetTop, sunsetBottom], startPoint: .top, endPoint: .bottom)
    static let sunsetHorizontal = LinearGradient(colors: [sunsetTop, sunsetBottom], startPoint: .leading, endPoint: .trailing)
    static let mountains = LinearGradient(colors: [mountainTop, mountainBottom], startPoint: .top, endPoint: .bottom)

    private static func p3(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(.displayP3, red: red / 255, green: green / 255, blue: blue / 255)
    }
}

/// The icon's motif as a live view: a film strip with one frame pulled out of it.
/// `plucked` runs from 0 (frame sitting in its slot) to 1 (fully pulled out).
struct PluckMark: View {
    var plucked: CGFloat = 1
    var size: CGFloat = 120

    var body: some View {
        let unit = size / 100
        let slot = CGRect(x: 19, y: 42.5, width: 18, height: 15)
        let pulled = CGRect(x: 40, y: 32, width: 50, height: 35)
        let card = CGRect(
            x: slot.minX + (pulled.minX - slot.minX) * plucked,
            y: slot.minY + (pulled.minY - slot.minY) * plucked,
            width: slot.width + (pulled.width - slot.width) * plucked,
            height: slot.height + (pulled.height - slot.height) * plucked
        )

        ZStack(alignment: .topLeading) {
            FilmStripShape()
                .frame(width: size, height: size)

            PluckedFrame(unit: unit)
                .frame(width: card.width * unit, height: card.height * unit)
                .rotationEffect(.degrees(7 * plucked))
                .shadow(color: .black.opacity(0.28 * plucked), radius: 10 * unit * plucked, y: 5 * unit * plucked)
                .position(x: card.midX * unit, y: card.midY * unit)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct FilmStripShape: View {
    var body: some View {
        Canvas { context, canvasSize in
            let unit = canvasSize.width / 100
            func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
                CGRect(x: x * unit, y: y * unit, width: width * unit, height: height * unit)
            }

            let strip = Path(roundedRect: rect(8, 0, 40, 100), cornerRadius: 7 * unit, style: .continuous)
            context.fill(strip, with: .color(Brand.film))

            var holes = Path()
            for row in stride(from: CGFloat(4), through: 92, by: 8.5) {
                holes.addRoundedRect(in: rect(11.5, row, 4, 4.8), cornerSize: CGSize(width: 1.2 * unit, height: 1.2 * unit))
                holes.addRoundedRect(in: rect(40.5, row, 4, 4.8), cornerSize: CGSize(width: 1.2 * unit, height: 1.2 * unit))
            }
            context.fill(holes, with: .color(.white.opacity(0.28)))

            var frames = Path()
            for offset in [-40.0, -20.0, 20.0, 40.0] {
                frames.addRoundedRect(in: rect(19, 42.5 + offset, 18, 15), cornerSize: CGSize(width: 2.4 * unit, height: 2.4 * unit))
            }
            context.fill(
                frames,
                with: .linearGradient(
                    Gradient(colors: [Brand.frameTop, Brand.frameBottom]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: canvasSize.height)
                )
            )

            // The empty slot the frame was plucked from.
            let slot = Path(roundedRect: rect(19, 42.5, 18, 15), cornerRadius: 2.4 * unit, style: .continuous)
            context.stroke(slot, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 0.9 * unit, dash: [2 * unit, 1.6 * unit]))
        }
    }
}

private struct PluckedFrame: View {
    let unit: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let inset = proxy.size.width * 0.075
            let radius = proxy.size.width * 0.12
            ZStack {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.white)

                ZStack(alignment: .topLeading) {
                    Brand.sunset
                    MountainShape()
                        .fill(Brand.mountains)
                    Circle()
                        .fill(Color(.displayP3, red: 1, green: 0.99, blue: 0.9))
                        .frame(width: proxy.size.height * 0.2, height: proxy.size.height * 0.2)
                        .offset(x: proxy.size.width * 0.14, y: proxy.size.height * 0.14)
                }
                .clipShape(RoundedRectangle(cornerRadius: max(1, radius - inset), style: .continuous))
                .padding(inset)
            }
        }
    }
}

private struct MountainShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: h * 0.72))
        path.addLine(to: CGPoint(x: w * 0.26, y: h * 0.44))
        path.addQuadCurve(to: CGPoint(x: w * 0.34, y: h * 0.44), control: CGPoint(x: w * 0.30, y: h * 0.38))
        path.addLine(to: CGPoint(x: w * 0.50, y: h * 0.62))
        path.addLine(to: CGPoint(x: w * 0.64, y: h * 0.34))
        path.addQuadCurve(to: CGPoint(x: w * 0.72, y: h * 0.34), control: CGPoint(x: w * 0.68, y: h * 0.27))
        path.addLine(to: CGPoint(x: w, y: h * 0.76))
        path.addLine(to: CGPoint(x: w, y: h))
        path.closeSubpath()
        return path
    }
}

/// Formats playback positions for the HUD in whichever style the viewer picked.
struct TimeFormatter {
    let frameRate: Double
    let secondsPerFrame: Double
    let duration: Double

    private var framesPerSecond: Int { max(1, Int(frameRate.rounded())) }

    /// The widest string `string(_:as:)` can produce for this video, with every digit
    /// zeroed, so labels can reserve a stable width and never nudge the scrubber.
    func widestString(as display: TimeDisplay) -> String {
        var widest = string(duration, as: display)
        if display == .timecode {
            // The frame field peaks at fps - 1, which the duration itself may not hit.
            let parts = widest.split(separator: ":")
            widest = parts.dropLast().joined(separator: ":") + ":" + String(repeating: "0", count: frameDigits)
        }
        return String(widest.map { $0.isNumber ? "0" : $0 })
    }

    private var frameDigits: Int { max(2, String(framesPerSecond - 1).count) }

    func string(_ seconds: Double, as display: TimeDisplay) -> String {
        guard seconds.isFinite else { return "--" }
        switch display {
        case .timecode:
            // Non-drop-frame SMPTE timecode, counted in whole frames.
            let fps = framesPerSecond
            let frame = frameIndex(seconds)
            let totalSeconds = frame / fps
            // Pad the frame field to the widest it gets, so 240 fps reads 007, not 7.
            return String(
                format: "%02d:%02d:%02d:%0*d",
                totalSeconds / 3600,
                (totalSeconds / 60) % 60,
                totalSeconds % 60,
                frameDigits,
                frame % fps
            )
        case .frames:
            return "\(frameIndex(seconds))"
        case .clock:
            let whole = max(0, Int(seconds))
            if duration >= 3600 {
                return String(format: "%d:%02d:%02d", whole / 3600, (whole / 60) % 60, whole % 60)
            }
            return String(format: "%02d:%02d", whole / 60, whole % 60)
        }
    }

    private func frameIndex(_ seconds: Double) -> Int {
        guard secondsPerFrame > 0 else { return 0 }
        return max(0, Int(floor(seconds / secondsPerFrame + 0.001)))
    }
}

/// A soft circular highlight for the borderless buttons inside the playback HUD.
struct HUDIconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        HUDIconButtonBody(configuration: configuration, diameter: diameter)
    }
}

private struct HUDIconButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let diameter: CGFloat
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .frame(width: diameter, height: diameter)
            .background {
                Circle()
                    .fill(.white.opacity(configuration.isPressed ? 0.24 : (isHovered ? 0.13 : 0)))
            }
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
            .onHover { isHovered = $0 }
    }
}
