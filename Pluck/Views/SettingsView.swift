import AppKit
import DMKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(PreferenceKey.captureFormat) private var captureFormat = CaptureFormat.png.rawValue
    @AppStorage(PreferenceKey.saveDestination) private var saveDestination = SaveDestination.askEveryTime.rawValue
    @AppStorage(PreferenceKey.jpegQuality) private var jpegQuality = 0.9
    @AppStorage(PreferenceKey.folderDisplayPath) private var folderDisplayPath = ""
    @Environment(\.hostingWindow) private var window

    var body: some View {
        Form {
            Section("Image") {
                Picker("Format", selection: $captureFormat) {
                    ForEach(CaptureFormat.allCases) { format in
                        Text(format.title).tag(format.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                if captureFormat == CaptureFormat.jpeg.rawValue {
                    HStack {
                        Text("JPEG quality")
                        Slider(value: $jpegQuality, in: 0.5...1, step: 0.05)
                        Text("\(Int(jpegQuality * 100))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }

            Section("Saving") {
                Picker("Destination", selection: $saveDestination) {
                    ForEach(SaveDestination.allCases) { destination in
                        Text(destination.title).tag(destination.rawValue)
                    }
                }

                if saveDestination == SaveDestination.chosenFolder.rawValue {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(folderDisplayPath.isEmpty ? "No folder chosen" : URL(fileURLWithPath: folderDisplayPath).lastPathComponent)
                                .lineLimit(1)
                            if !folderDisplayPath.isEmpty {
                                Text(folderDisplayPath)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }

                        Spacer()

                        Button(folderDisplayPath.isEmpty ? "Choose…" : "Change…") {
                            chooseFolder()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: DMLayout.settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 8)
        .onChange(of: saveDestination) { _, newValue in
            if newValue == SaveDestination.chosenFolder.rawValue, folderDisplayPath.isEmpty {
                chooseFolder()
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Capture Folder"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        Task {
            if await panel.present(in: window) == .OK, let folderURL = panel.url {
                do {
                    try FolderBookmarkStore.save(folderURL)
                    folderDisplayPath = folderURL.path
                } catch {
                    saveDestination = SaveDestination.askEveryTime.rawValue
                }
            } else if folderDisplayPath.isEmpty {
                saveDestination = SaveDestination.askEveryTime.rawValue
            }
        }
    }
}

