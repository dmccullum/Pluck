import SwiftUI

@main
struct ShotgrabberApp: App {
    @StateObject private var windowState = AppWindowState()

    var body: some Scene {
        WindowGroup("Shotgrabber", id: "main", for: URL.self) { $documentURL in
            VideoDocumentWindow(
                initialURL: documentURL,
                isMainWindow: documentURL == nil,
                windowState: windowState
            )
        }
        .defaultSize(width: 480, height: 480)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            VideoDocumentCommands(windowState: windowState)
        }

        Settings {
            SettingsView()
        }

        Window("About Shotgrabber", id: "about") {
            AboutView()
        }
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

private struct VideoDocumentWindow: View {
    let initialURL: URL?
    let isMainWindow: Bool
    @ObservedObject var windowState: AppWindowState

    @StateObject private var model = VideoPlayerModel()
    @State private var windowIdentity = UUID()
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView(model: model)
            .navigationTitle(model.videoURL?.lastPathComponent ?? "Shotgrabber")
            .background {
                WindowAspectConfigurator(
                    aspectRatio: model.videoAspectRatio,
                    hasVideo: model.hasVideo,
                    controlsVisible: model.controlsVisible,
                    presentationID: model.presentationID,
                    onPresentationReady: { id in
                        model.finishPresentation(id: id)
                    }
                )
            }
            .focusedSceneValue(\.videoDocumentActions, actions)
            .task(id: initialURL) {
                guard let initialURL, model.videoURL != initialURL else { return }
                model.open(url: initialURL)
            }
            .onAppear {
                if isMainWindow {
                    windowState.setMainWindow(id: windowIdentity, visible: true)
                }
                model.documentOpener = { [weak model] url in
                    guard let model else { return }
                    if model.hasVideo {
                        openWindow(value: url)
                    } else {
                        model.open(url: url)
                    }
                }
            }
            .onDisappear {
                model.stopPlayback()
                model.documentOpener = nil
                if isMainWindow {
                    windowState.setMainWindow(id: windowIdentity, visible: false)
                }
            }
            .onOpenURL { url in
                if model.hasVideo {
                    openWindow(value: url)
                } else {
                    model.open(url: url)
                }
            }
    }

    private var actions: VideoDocumentActions {
        VideoDocumentActions(
            openVideo: model.presentOpenPanel,
            captureFrame: model.captureCurrentFrame,
            copyFrame: model.copyCurrentFrame,
            togglePlayback: model.togglePlayback,
            shuttleBackward: model.shuttleBackward,
            pausePlayback: model.stopPlayback,
            shuttleForward: model.shuttleForward,
            previousFrame: { model.stepFrame(by: -1) },
            nextFrame: { model.stepFrame(by: 1) },
            jumpBackward: { model.seekBy(-5) },
            jumpForward: { model.seekBy(5) },
            goToStart: model.seekToStart,
            goToEnd: model.seekToEnd,
            hasVideo: model.hasVideo,
            isPlaying: model.isPlaying,
            isCapturing: model.isCapturing
        )
    }
}

@MainActor
private final class AppWindowState: ObservableObject {
    @Published private var visibleMainWindowIDs: Set<UUID> = []

    var isMainWindowVisible: Bool {
        !visibleMainWindowIDs.isEmpty
    }

    func setMainWindow(id: UUID, visible: Bool) {
        if visible {
            visibleMainWindowIDs.insert(id)
        } else {
            visibleMainWindowIDs.remove(id)
        }
    }
}

private struct VideoDocumentActions {
    let openVideo: () -> Void
    let captureFrame: () -> Void
    let copyFrame: () -> Void
    let togglePlayback: () -> Void
    let shuttleBackward: () -> Void
    let pausePlayback: () -> Void
    let shuttleForward: () -> Void
    let previousFrame: () -> Void
    let nextFrame: () -> Void
    let jumpBackward: () -> Void
    let jumpForward: () -> Void
    let goToStart: () -> Void
    let goToEnd: () -> Void
    let hasVideo: Bool
    let isPlaying: Bool
    let isCapturing: Bool
}

private struct VideoDocumentActionsKey: FocusedValueKey {
    typealias Value = VideoDocumentActions
}

private extension FocusedValues {
    var videoDocumentActions: VideoDocumentActions? {
        get { self[VideoDocumentActionsKey.self] }
        set { self[VideoDocumentActionsKey.self] = newValue }
    }
}

private struct VideoDocumentCommands: Commands {
    @FocusedValue(\.videoDocumentActions) private var actions
    @ObservedObject var windowState: AppWindowState
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Shotgrabber") {
                openWindow(id: "about")
            }
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button("Open Video…") {
                actions?.openVideo()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(actions == nil)
        }

        CommandGroup(after: .saveItem) {
            Button("Save Frame") {
                actions?.captureFrame()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(actions?.hasVideo != true || actions?.isCapturing == true)
        }

        CommandGroup(after: .pasteboard) {
            Button("Copy Frame") {
                actions?.copyFrame()
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(actions?.hasVideo != true || actions?.isCapturing == true)
        }

        CommandMenu("Playback") {
            Button(actions?.isPlaying == true ? "Pause" : "Play") {
                actions?.togglePlayback()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(actions?.hasVideo != true)

            Divider()

            Button("Shuttle Reverse") {
                actions?.shuttleBackward()
            }
            .keyboardShortcut("j", modifiers: [])
            .disabled(actions?.hasVideo != true)

            Button("Pause") {
                actions?.pausePlayback()
            }
            .keyboardShortcut("k", modifiers: [])
            .disabled(actions?.hasVideo != true)

            Button("Shuttle Forward") {
                actions?.shuttleForward()
            }
            .keyboardShortcut("l", modifiers: [])
            .disabled(actions?.hasVideo != true)

            Divider()

            Button("Previous Frame") {
                actions?.previousFrame()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .disabled(actions?.hasVideo != true)

            Button("Next Frame") {
                actions?.nextFrame()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .disabled(actions?.hasVideo != true)

            Divider()

            Button("Back 5 Seconds") {
                actions?.jumpBackward()
            }
            .keyboardShortcut(.leftArrow, modifiers: .shift)
            .disabled(actions?.hasVideo != true)

            Button("Forward 5 Seconds") {
                actions?.jumpForward()
            }
            .keyboardShortcut(.rightArrow, modifiers: .shift)
            .disabled(actions?.hasVideo != true)

            Button("Go to Start") {
                actions?.goToStart()
            }
            .keyboardShortcut(.home, modifiers: [])
            .disabled(actions?.hasVideo != true)

            Button("Go to End") {
                actions?.goToEnd()
            }
            .keyboardShortcut(.end, modifiers: [])
            .disabled(actions?.hasVideo != true)
        }

        CommandGroup(before: .windowList) {
            if !windowState.isMainWindowVisible {
                Button("Shotgrabber") {
                    openWindow(id: "main")
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()
            }
        }
    }
}
