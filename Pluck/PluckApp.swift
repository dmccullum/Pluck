import DMKit
import SwiftUI

@main
struct PluckApp: App {
    var body: some Scene {
        WindowGroup("Pluck", id: "main", for: VideoReference.self) { $reference in
            VideoDocumentWindow(reference: $reference)
        }
        .defaultSize(width: 480, height: 480)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            VideoDocumentCommands()
            FamilyHelpCommands(
                help: URL(string: "https://github.com/dmccullum/Pluck#readme")!,
                keyboardShortcuts: .url(URL(string: "https://github.com/dmccullum/Pluck#keyboard-shortcuts")!),
                reportIssue: URL(string: "https://github.com/dmccullum/Pluck/issues/new")
            )
        }

        Settings {
            SettingsView()
        }

        AboutScene(links: AboutLinks(sourceCode: URL(string: "https://github.com/dmccullum/Pluck"))) {
            FilmToPhotoCapsule()
        }
    }
}

private struct VideoDocumentWindow: View {
    /// The window's restorable value: nil for an empty window until it opens a video.
    @Binding var reference: VideoReference?

    @State private var model = VideoPlayerModel()
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
                model.documentOpener = { [model] url in
                    open(url, in: model)
                }
            }
            .onDisappear {
                model.stopPlayback()
                model.documentOpener = nil
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
            showInFinder: model.showVideoInFinder,
            setSafeZone: model.setSafeZone,
            setIncludesSafeZoneInCaptures: model.setIncludesSafeZoneInCaptures,
            hasVideo: model.hasVideo,
            isCapturing: model.isCapturing,
            supportsSafeZone: model.supportsSafeZone,
            safeZone: model.safeZone,
            includesSafeZoneInCaptures: model.includesSafeZoneInCaptures
        )
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
    let showInFinder: () -> Void
    let setSafeZone: (SafeZone) -> Void
    let setIncludesSafeZoneInCaptures: (Bool) -> Void
    let hasVideo: Bool
    let isCapturing: Bool
    let supportsSafeZone: Bool
    let safeZone: SafeZone
    let includesSafeZoneInCaptures: Bool
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
    var recents = RecentVideos.shared
    @Environment(\.openWindow) private var openWindow
    @AppStorage(PreferenceKey.saveDestination) private var saveDestination = SaveDestination.askEveryTime.rawValue
    @AppStorage(PreferenceKey.timeDisplay) private var timeDisplay = TimeDisplay.timecode.rawValue

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Button("Open Video…") {
                if let actions {
                    actions.openVideo()
                } else {
                    openVideoInNewWindow()
                }
            }
            .keyboardShortcut("o", modifiers: .command)

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
            Button(SaveDestination.saveFrameTitle(forRawValue: saveDestination)) {
                actions?.captureFrame()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(actions?.hasVideo != true || actions?.isCapturing == true)

            Divider()

            Button("Show Video in Finder") {
                actions?.showInFinder()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(actions?.hasVideo != true)
        }

        // The windows have no text to edit, so Copy copies the frame and the other edit items go.
        CommandGroup(replacing: .pasteboard) {
            Button("Copy Frame") {
                actions?.copyFrame()
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(actions?.hasVideo != true || actions?.isCapturing == true)
        }

        CommandGroup(before: .toolbar) {
            SafeZonePicker(selection: Binding(
                get: { actions?.safeZone ?? .off },
                set: { actions?.setSafeZone($0) }
            ))
            .disabled(actions?.supportsSafeZone != true)

            Toggle("Include Safe Zone in Saved Frames", isOn: Binding(
                get: { actions?.includesSafeZoneInCaptures == true },
                set: { actions?.setIncludesSafeZoneInCaptures($0) }
            ))
            .disabled(actions?.supportsSafeZone != true || actions?.safeZone == .off)

            Divider()

            Picker("Time Display", selection: $timeDisplay) {
                ForEach(TimeDisplay.allCases, id: \.self) { display in
                    Text(display.title).tag(display.rawValue)
                }
            }
            .pickerStyle(.menu)

            Divider()
        }

        CommandMenu("Playback") {
            Button("Play/Pause") {
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
    }

    /// With no video window to attach a sheet to, runs the panel app-modally.
    private func openVideoInNewWindow() {
        Task {
            if let url = await VideoPlayerModel.makeOpenPanel().present(in: nil) {
                openWindow(value: VideoReference(url: url))
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
