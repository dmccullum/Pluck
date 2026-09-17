import SwiftUI

struct DropScreen: View {
    @ObservedObject var model: VideoPlayerModel
    let isTargeted: Bool
    @Environment(\.openSettings) private var openSettings
    @AppStorage(PreferenceKey.captureFormat) private var captureFormat = CaptureFormat.png.rawValue
    @AppStorage(PreferenceKey.saveDestination) private var saveDestination = SaveDestination.askEveryTime.rawValue
    @AppStorage(PreferenceKey.folderDisplayPath) private var folderDisplayPath = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 15) {
                Image(systemName: isTargeted ? "arrow.down.circle.fill" : "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 48, weight: .light))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(isTargeted ? 1.06 : 1)

                Text(isTargeted ? "Let go to open" : "Drop a video to begin")
                    .font(.title2.weight(.semibold))

                Button("Choose Video…") {
                    model.presentOpenPanel()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
            .contentShape(Rectangle())
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.tint, style: StrokeStyle(lineWidth: 3, dash: [9, 6]))
                        .padding(14)
                        .allowsHitTesting(false)
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: isTargeted)

            statusBar
        }
        .background(.background)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(destinationTitle)
                    .lineLimit(1)
                Button("Change…") {
                    openSettings()
                }
                .buttonStyle(.link)
            }

            Spacer(minLength: 20)

            Picker("Capture format", selection: $captureFormat) {
                ForEach(CaptureFormat.allCases) { format in
                    Text(format.title)
                        .tag(format.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var destinationTitle: String {
        if saveDestination == SaveDestination.chosenFolder.rawValue, !folderDisplayPath.isEmpty {
            return URL(fileURLWithPath: folderDisplayPath).lastPathComponent
        }
        return "Ask where to save"
    }
}
