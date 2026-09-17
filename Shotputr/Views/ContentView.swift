import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: VideoPlayerModel
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

            if let toast = model.toastMessage {
                toastPlacement(toast)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.32, dampingFraction: 0.86), value: toast)
            }
        }
        .animation(.easeOut(duration: 0.22), value: model.isPresentationReady)
        .frame(
            minWidth: minimumContentSize.width,
            idealWidth: model.hasVideo ? 980 : 700,
            minHeight: minimumContentSize.height,
            idealHeight: model.hasVideo ? 700 : 400
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            return model.handleDrop(url: url)
        } isTargeted: { targeted in
            isDropTargeted = targeted
        }
        .alert("Shotgrabber", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
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

    @ViewBuilder
    private func toastPlacement(_ message: String) -> some View {
        if model.hasVideo {
            VStack {
                ToastView(message: message)
                    .padding(.top, 18)
                Spacer()
            }
        } else {
            VStack {
                Spacer()
                ToastView(message: message)
                    .padding(.bottom, 26)
            }
        }
    }
}

private struct WindowBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor)
        .ignoresSafeArea()
    }
}

private struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color.accentColor.opacity(0.14),
                    Color.accentColor.opacity(0.025),
                    .clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 280
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 58, height: 58)

                    Circle()
                        .stroke(Color.accentColor.opacity(0.22), lineWidth: 1)
                        .frame(width: 58, height: 58)

                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 25, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                }

                ProgressView()
                    .controlSize(.small)

                Text("Preparing video…")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(28)
        }
        .transition(.opacity)
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 15)
            .padding(.vertical, 10)
            .background(.thickMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}
