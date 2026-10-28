import SwiftUI

@main
struct PluckApp: App {
    @State private var windowState = AppWindowState()

    var body: some Scene {
        WindowGroup("Pluck", id: "main", for: VideoReference.self) { $reference in
            VideoDocumentWindow(reference: $reference, windowState: windowState)
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

        Window("About Pluck", id: "about") {
            AboutView()
        }
        .defaultPosition(.center)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .restorationBehavior(.disabled)
    }
}

private struct VideoDocumentWindow: View {
    /// The window's restorable value: nil for an empty window until it opens a video.
    @Binding var reference: VideoReference?
    var windowState: AppWindowState

    @State private var model = VideoPlayerModel()
    @State private var windowIdentity = UUID()
    /// Whether this window started empty, captured once so opening a video doesn't change it.
    @State private var isMainWindow: Bool?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ContentView(model: model)
            .navigationTitle(model.videoURL?.lastPathComponent ?? "Pluck")
            .background {
                WindowAspectConfigurator(
                    aspectRatio: model.videoAspectRatio,
                    hasVideo: model.hasVideo,
                    controlsVisible: model.controlsVisible,
                    presentationID: model.presentationID,
                    onWindowAvailable: { window in
                        model.window = window
                    },
                    onPresentationReady: { id in
                        model.finishPresentation(id: id)
                    }
                )
            }
            .focusedSceneValue(\.videoDocumentActions, actions)
            .task(id: reference) {
                guard let reference, model.videoURL != reference.url else { return }
                model.open(url: reference.resolve())
            }
            .onChange(of: model.videoURL) { _, url in
                // Keep the restorable value in step, so a relaunch reopens this window's video.
                if let url, url != reference?.url {
                    reference = VideoReference(url: url)
                }
            }
            .onAppear {
                if isMainWindow == nil {
                    isMainWindow = reference == nil
                }
                if isMainWindow == true {
                    windowState.setMainWindow(id: windowIdentity, visible: true)
                }
                model.documentOpener = { [model] url in
                    open(url, in: model)
                }
            }
            .onDisappear {
                model.stopPlayback()
                model.documentOpener = nil
                if isMainWindow == true {
                    windowState.setMainWindow(id: windowIdentity, visible: false)
                }
            }
            .onOpenURL { url in
                open(url, in: model)
            }
    }

    /// Opens `url` here if this window is empty, otherwise in a new window.
    /// A window still loading a video counts as occupied, so a batch of files each gets a window.
    private func open(_ url: URL, in model: VideoPlayerModel) {
        if model.hasVideo || model.isLoading {
            openWindow(value: VideoReference(url: url))
        } else {
            model.open(url: url)
        }
    }

    private var actions: VideoDocumentActions {
        VideoDocumentActions(
            openVideo: model.presentOpenPanel,
            openURL: model.requestOpen(url:),
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

@Observable
private final class AppWindowState {
    private var visibleMainWindowIDs: Set<UUID> = []

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
    let openURL: (URL) -> Void
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
    var windowState: AppWindowState
    var recents = RecentVideos.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Pluck") {
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

            Menu("Open Recent") {
                ForEach(recents.videos, id: \.self) { video in
                    Button(video.url.lastPathComponent) {
                        openRecent(video)
                    }
                }
                if !recents.videos.isEmpty {
                    Divider()
                }
                Button("Clear Menu") {
                    recents.clear()
                }
                .disabled(recents.videos.isEmpty)
            }
        }

        CommandGroup(after: .saveItem) {
            Button("Save Frame") {
                actions?.captureFrame()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(actions?.hasVideo != true || actions?.isCapturing == true)
        }

        // The windows have no text to edit, so Copy copies the frame and the other edit items go.
        CommandGroup(replacing: .pasteboard) {
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
                Button("Pluck") {
                    openWindow(id: "main")
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()
            }
        }
    }

    private func openRecent(_ video: VideoReference) {
        // An empty window opens it in place; otherwise the new window resolves the bookmark itself.
        if let actions, !actions.hasVideo {
            actions.openURL(video.resolve())
        } else {
            openWindow(value: video)
        }
    }
}
