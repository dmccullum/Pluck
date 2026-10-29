import DMKit
import SwiftUI

struct DropScreen: View {
    var model: VideoPlayerModel
    @State private var isTargeted = false
    @Environment(\.openSettings) private var openSettings
    @AppStorage(PreferenceKey.captureFormat) private var captureFormat = CaptureFormat.png.rawValue
    @AppStorage(PreferenceKey.saveDestination) private var saveDestination = SaveDestination.askEveryTime.rawValue
    @AppStorage(PreferenceKey.folderDisplayPath) private var folderDisplayPath = ""
    @State private var hasAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            DropBackdrop()

            VStack(spacing: 0) {
                PluckMark(plucked: isTargeted ? 1 : (hasAppeared ? 0.82 : 0), size: 124)
                    .scaleEffect(isTargeted && !reduceMotion ? 1.08 : 1)
                    .padding(.bottom, 14)

                Text(isTargeted ? "Let go to open" : "Drop a video to begin")
                    .font(.title2.weight(.semibold))
                    .contentTransition(.opacity)

                Text("Find the exact frame, then save or copy it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Button("Open Video…") {
                    model.presentOpenPanel()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 20)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())

            VStack {
                Spacer()
                capturePill
                    .padding(.bottom, 18)
            }
        }
        .dmAnimation(.spring, value: isTargeted)
        .dropTarget(for: URL.self, isTargeted: $isTargeted) { urls, _ in
            model.handleDrop(urls: urls)
        }
        .task {
            guard !reduceMotion else {
                hasAppeared = true
                return
            }
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                hasAppeared = true
            }
        }
    }

    private var capturePill: some View {
        HStack(spacing: 10) {
            Button {
                openSettings()
            } label: {
                Label(destinationTitle, systemImage: saveDestination == SaveDestination.chosenFolder.rawValue ? "folder.fill" : "folder")
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Change where frames are saved")

            Divider()
                .frame(height: 14)

            Menu {
                Picker("Capture format", selection: $captureFormat) {
                    ForEach(CaptureFormat.allCases) { format in
                        Text(format.title).tag(format.rawValue)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 4) {
                    Text(CaptureFormat(rawValue: captureFormat)?.title ?? "PNG")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Image format for saved frames")
        }
        .font(.callout)
        .foregroundStyle(.primary.opacity(0.85))
        .padding(.horizontal, 16)
        .frame(height: 36)
        .glassEffect(.regular, in: .capsule)
    }

    private var destinationTitle: String {
        if saveDestination == SaveDestination.chosenFolder.rawValue, !folderDisplayPath.isEmpty {
            return URL(fileURLWithPath: folderDisplayPath).lastPathComponent
        }
        return "Ask where to save"
    }
}

/// A faint wash of the icon's sky and sunset behind the empty window.
private struct DropBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let strength = colorScheme == .dark ? 1.4 : 1.0
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Brand.skyTop.opacity(0.2 * strength), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 560
            )
            RadialGradient(
                colors: [Brand.sunsetBottom.opacity(0.09 * strength), .clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 480
            )
        }
        .ignoresSafeArea()
    }
}
