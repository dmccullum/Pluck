import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    var model: VideoPlayerModel
    @State private var isDropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

            if let toast = model.toast {
                toastPlacement(toast)
                    .id(toast.id)
                    .transition(reduceMotion ? .opacity : .move(edge: model.hasVideo ? .top : .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: model.toast)
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
        .alert("Pluck", isPresented: Binding(
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
    private func toastPlacement(_ toast: Toast) -> some View {
        if model.hasVideo {
            VStack {
                ToastView(toast: toast, onDismiss: model.dismissToast)
                    .padding(.top, 44)
                Spacer()
            }
        } else {
            VStack {
                Spacer()
                ToastView(toast: toast, onDismiss: model.dismissToast)
                    .padding(.bottom, 72)
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

private struct ToastView: View {
    let toast: Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            if let thumbnail = toast.thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 48, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.white, lineWidth: 1.5)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                    .rotationEffect(.degrees(-5))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: toast.systemImage)
                            .font(.system(size: 13, weight: .bold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .background(Circle().fill(.white).padding(2))
                            .offset(x: 6, y: 5)
                    }
            } else {
                Image(systemName: toast.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tint)
            }

            Text(toast.message)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 340, alignment: .leading)

            if let url = toast.revealURL {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    onDismiss()
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(.leading, toast.thumbnail == nil ? 15 : 10)
        .padding(.trailing, toast.revealURL == nil ? 16 : 7)
        .padding(.vertical, 7)
        .frame(minHeight: 44)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular.interactive(toast.revealURL != nil), in: .capsule)
        .modifier(HugContentWidth())
        .padding(.horizontal, 20)
    }
}

/// Sizes a view to its natural width, but never wider than its container offers,
/// so a long message truncates instead of stretching the window's layout.
private struct HugContentWidth: ViewModifier {
    func body(content: Content) -> some View {
        HugContentWidthLayout { content }
    }
}

private struct HugContentWidthLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let ideal = subview.sizeThatFits(.unspecified)
        let width = min(ideal.width, proposal.width ?? ideal.width)
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}
