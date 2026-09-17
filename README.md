# Shotgrabber

Shotgrabber is a small, native macOS app for opening a video, finding the exact frame you want, and saving it as an image.

## What it does

- Opens videos by dropping them into the window, dropping them on the app icon, using **Open With**, or pressing **Command-O**.
- Gives every opened video its own document window and independent playback state.
- Plays and scrubs video with a deliberately minimal interface.
- Steps backward or forward by one source frame with the arrow keys.
- Captures the current frame with **Command-S**.
- Exports PNG, JPEG, HEIC, or TIFF.
- Either asks where to save every capture or remembers a destination folder.
- Resizes the document window to the source aspect ratio and overlays a QuickTime-style Liquid Glass control HUD.

## Build

Open `Shotputr.xcodeproj` in Xcode and run the `Shotputr` scheme, or build from Terminal:

```sh
xcodebuild -project Shotputr.xcodeproj -scheme Shotputr -configuration Debug build
```

Shotgrabber targets macOS 26 or later so it can use the same native Liquid Glass controls as its sister app, Filmify. It uses only Apple frameworks (SwiftUI, AppKit, AVFoundation, and UniformTypeIdentifiers).

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Open video | Command-O |
| Play / pause | Space |
| Previous frame | Left Arrow |
| Next frame | Right Arrow |
| Save frame | Command-S |
| Settings | Command-, |
