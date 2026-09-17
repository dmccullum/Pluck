import AVFoundation
import SwiftUI

struct PlayerScreen: View {
    @ObservedObject var model: VideoPlayerModel
    let player: AVPlayer

    @State private var controlsVisible = true
    @State private var hideControlsTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VideoCanvas(model: model, player: player)
                controlsLayer(compact: proxy.size.width < 520)
            }
        }
        .background(.black)
        .animation(.easeOut(duration: 0.18), value: controlsVisible)
        .onContinuousHover { phase in
            switch phase {
            case .active:
                showControls(andScheduleHide: model.isPlaying)
            case .ended:
                scheduleControlsHideIfPlaying()
            }
        }
        .onChange(of: model.isPlaying) { _, isPlaying in
            if isPlaying {
                scheduleControlsHideIfPlaying()
            } else {
                hideControlsTask?.cancel()
                controlsVisible = true
            }
        }
        .onDisappear {
            hideControlsTask?.cancel()
        }
        .environment(\.playerControlsVisible, controlsVisible)
    }

    @ViewBuilder
    private func controlsLayer(compact: Bool) -> some View {
        if compact {
            VStack(spacing: 10) {
                Spacer()

                HStack {
                    OverlayButton(model: model)
                    Spacer()
                    CaptureButton(model: model)
                }
                .padding(.horizontal, 18)

                PlaybackHUD(model: model)
                    .frame(maxWidth: 480)
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
                        OverlayButton(model: model)
                        Spacer()
                    }
                    .padding(.leading, 24)
                    .padding(.bottom, 28)
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        CaptureButton(model: model)
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 28)
                }
            }
        }
    }

    private func showControls(andScheduleHide shouldHide: Bool) {
        hideControlsTask?.cancel()
        controlsVisible = true
        if shouldHide {
            scheduleControlsHideIfPlaying()
        }
    }

    private func scheduleControlsHideIfPlaying() {
        guard model.isPlaying else { return }
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                controlsVisible = false
            }
        }
    }
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
    @State private var isPopoverPresented = false

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("PNG Overlay")

                if model.hasOverlay {
                    Circle()
                        .fill(model.isOverlayEnabled ? Color.green : Color.secondary)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(.white.opacity(0.75), lineWidth: 1))
                        .offset(x: 1, y: -1)
                }
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .help(model.hasOverlay ? "PNG Overlay: \(model.overlayName ?? "")" : "Add PNG Overlay")
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
                .keyboardShortcut(.leftArrow, modifiers: [])

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
                .keyboardShortcut(.rightArrow, modifiers: [])
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
}

private struct CaptureButton: View {
    @ObservedObject var model: VideoPlayerModel
    @Environment(\.playerControlsVisible) private var controlsVisible

    var body: some View {
        Button {
            model.captureCurrentFrame()
        } label: {
            Image(systemName: model.isCapturing ? "hourglass" : "camera.shutter.button.fill")
                .font(.system(size: 17, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 28, height: 28)
                .accessibilityLabel(model.isCapturing ? "Saving Frame" : "Save Frame")
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .keyboardShortcut("s", modifiers: .command)
        .disabled(model.isCapturing)
        .help("Save Frame (Command-S)")
        .opacity(controlsVisible ? 1 : 0)
        .scaleEffect(controlsVisible ? 1 : 0.92)
        .allowsHitTesting(controlsVisible)
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
        .help(title + (title == "Previous Frame" ? " (Left Arrow)" : " (Right Arrow)"))
    }
}
