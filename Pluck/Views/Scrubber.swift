import SwiftUI

/// Timeline scrubber with a QuickTime-style frame preview while hovering.
struct Scrubber: View {
    @ObservedObject var model: VideoPlayerModel
    /// How far above the track the preview floats, so it can clear surrounding controls.
    var previewLift: CGFloat = 16
    let label: (Double) -> String

    @State private var hoverX: CGFloat?
    @State private var previewImage: CGImage?
    @State private var previewTask: Task<Void, Never>?
    @State private var isDragging = false

    private let previewWidth: CGFloat = 168

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let progress = model.duration > 0 ? CGFloat(model.currentTime / model.duration) : 0
            let isActive = hoverX != nil || isDragging
            let trackHeight: CGFloat = isActive ? 6 : 4
            let knobSize: CGFloat = isDragging ? 15 : 12

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(height: trackHeight)

                if let hoverX, !isDragging {
                    Capsule()
                        .fill(.white.opacity(0.16))
                        .frame(width: max(trackHeight, hoverX), height: trackHeight)
                }

                Capsule()
                    .fill(Brand.sunsetHorizontal)
                    .frame(width: max(trackHeight, width * progress), height: trackHeight)

                Circle()
                    .fill(.white)
                    .frame(width: knobSize, height: knobSize)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .offset(x: width * progress - knobSize / 2)
            }
            .frame(width: width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            model.beginScrubbing()
                        }
                        model.scrub(to: seconds(at: value.location.x, width: width))
                    }
                    .onEnded { _ in
                        isDragging = false
                        model.endScrubbing()
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let x = min(max(0, location.x), width)
                    hoverX = x
                    requestPreview(at: seconds(at: x, width: width))
                case .ended:
                    hoverX = nil
                    previewTask?.cancel()
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let hoverX, !isDragging {
                    preview(at: seconds(at: hoverX, width: width))
                        .offset(
                            x: min(max(hoverX - previewWidth / 2, -24), width - previewWidth + 24),
                            y: -(proxy.size.height + previewLift)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
                }
            }
            .animation(.easeOut(duration: 0.14), value: isActive)
            .animation(.easeOut(duration: 0.14), value: hoverX == nil)
        }
        .frame(height: 16)
        .accessibilityRepresentation {
            Slider(
                value: Binding(get: { model.currentTime }, set: { model.scrub(to: $0) }),
                in: 0...max(model.duration, 0.001)
            )
        }
        .onDisappear { previewTask?.cancel() }
    }

    private func preview(at seconds: Double) -> some View {
        VStack(spacing: 5) {
            ZStack {
                Rectangle().fill(.black)
                if let previewImage {
                    Image(decorative: previewImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(width: previewWidth - 10, height: (previewWidth - 10) / CGFloat(max(0.3, min(model.videoAspectRatio, 4))))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(label(seconds))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .padding(5)
        .padding(.bottom, 1)
        .frame(width: previewWidth)
        .glassEffect(.regular.tint(.black.opacity(0.35)), in: .rect(cornerRadius: 13))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
        .allowsHitTesting(false)
    }

    private func seconds(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(max(0, x / width), 1)) * model.duration
    }

    private func requestPreview(at seconds: Double) {
        if let cached = model.cachedPreview(at: seconds) {
            previewImage = cached
        }
        previewTask?.cancel()
        previewTask = Task {
            // Only pay for a sharp decode once the pointer settles.
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            let image = await model.previewImage(at: seconds)
            guard !Task.isCancelled, let image else { return }
            previewImage = image
        }
    }
}
