# Pluck

Pluck is a small, native macOS app for opening a video, finding the exact frame you want, and saving it as an image.

## What it does

- Opens videos by dropping them into the window, dropping them on the app icon, using **Open With**, or pressing **Command-O**.
- Gives every opened video its own document window and independent playback state.
- Plays and scrubs video with a deliberately minimal interface.
- Steps backward or forward by one source frame with the arrow keys, comma/period, or K+J/K+L.
- Saves the current frame with **Command-S**, or copies it to the clipboard with **Command-C**.
- Shows the position as timecode, frame number, or minutes and seconds; click the time to switch.
- Previews frames when you hover over the timeline.
- Shows safe zone guides (Instagram Reels, or Meta's stricter ads layout) from the safe zone button; Command-click it to turn the guide on or off. Optionally include it in saved and copied frames.
- Exports PNG, JPEG, HEIC, or TIFF.
- Either asks where to save every capture or remembers a destination folder.
- Resizes the document window to the source aspect ratio. The title bar and Liquid Glass controls fade away after inactivity and return when you move the pointer.

## Build

Double-click `build.command` to build a Release copy into `Build/Pluck.app` and open it.

Or open `Pluck.xcodeproj` in Xcode and run the `Pluck` scheme, or build from Terminal:

```sh
xcodebuild -project Pluck.xcodeproj -scheme Pluck -configuration Debug build
```

Pluck targets macOS 26 or later so it can use the same native Liquid Glass controls as its sister app, Filmify. It uses only Apple frameworks (SwiftUI, AppKit, AVFoundation, and UniformTypeIdentifiers).

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Open video | Command-O |
| Play / pause | Space |
| Shuttle backward (repeat for 2×, 4×, 8×) | J |
| Pause | K |
| Shuttle forward (repeat for 2×, 4×, 8×) | L |
| Previous frame | Left Arrow, comma, or hold K and tap J |
| Next frame | Right Arrow, period, or hold K and tap L |
| Jump backward / forward 5 seconds | Shift-Left / Shift-Right |
| Go to start / end | Home / End |
| Save frame | Command-S |
| Copy frame | Command-C |
| Settings | Command-, |
