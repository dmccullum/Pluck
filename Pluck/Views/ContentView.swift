import AppKit
import DMKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var model: VideoPlayerModel
    @State private var isDropTargeted = false

    var body: some View {
        ZStack {
            WindowBackground()

            Group {
                if model.hasVideo,
                   model.isPresentationReady,
                   let player = model.player {
                    PlayerScreen(model: model, player: player)
                        .transition(.opacity)
                } else if model.hasVideo {
                    Color.clear
                } else {
                    DropScreen(model: model, isTargeted: isDropTargeted)
                }
            }

            if model.isLoading {
                LoadingOverlay()
            }
        }
        // Statuses follow a capture or a safe zone change, so there's always a video under them.
        .statusCapsule($model.status, alignment: .top)
        .animation(.easeOut(duration: 0.22), value: model.isPresentationReady)
        .frame(
            minWidth: minimumContentSize.width,
            idealWidth: model.hasVideo ? 980 : 700,
            minHeight: minimumContentSize.height,
            idealHeight: model.hasVideo ? 700 : 400
        )
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDrop(urls: urls)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .alert(model.alert?.title ?? "", isPresented: Binding(
            get: { model.alert != nil },
            set: { if !$0 { model.alert = nil } }
        ), presenting: model.alert) { _ in
            Button("OK", role: .cancel) { model.alert = nil }
        } message: { alert in
            Text(alert.message)
        }
    }

    private var minimumContentSize: CGSize {
        guard model.hasVideo,
              model.isPresentationReady,
              model.videoAspectRatio.isFinite,
              model.videoAspectRatio > 0 else {
            return CGSize(width: 400, height: 400)
        }

        let minimumWidth = model.videoAspectRatio < 0.8 ? 400.0 : 560.0
        return CGSize(
            width: minimumWidth,
            height: minimumWidth / model.videoAspectRatio
        )
    }
}

private struct WindowBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
        .ignoresSafeArea()
    }
}

private struct LoadingOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            RadialGradient(
                colors: [Brand.skyTop.opacity(0.16), Brand.skyBottom.opacity(0.03), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 300
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                if reduceMotion {
                    PluckMark(plucked: 0.82, size: 84)
                } else {
                    PhaseAnimator([0.0, 1.0]) { phase in
                        PluckMark(plucked: phase, size: 84)
                    } animation: { phase in
                        phase == 1
                            ? .spring(response: 0.7, dampingFraction: 0.72).delay(0.15)
                            : .easeInOut(duration: 0.5).delay(0.5)
                    }
                }

                Text("Preparing video…")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .transition(.opacity)
    }
}
