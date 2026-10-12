<p align="center">
  <img src="docs/icon.png" width="128" alt="Pluck app icon">
</p>

<h1 align="center">Pluck</h1>

<p align="center">
  Play or step through a video frame by frame and save any frame as an image.
</p>

<p align="center">
  <img src="docs/screenshot.png" width="420" alt="Pluck playing a vertical video with the Reels safe zone guide">
</p>

## Features

- Step one source frame at a time with the arrow keys, comma and period, or K+J / K+L.
- Save the current frame with <kbd>⌘S</kbd> or copy it with <kbd>⌘C</kbd>. Formats: PNG, JPEG, HEIC, TIFF.
- Hover over the timeline to preview the frame under the pointer.
- Show Instagram Reels or Meta ads safe zone guides on 9:16 videos, and optionally include them in saved and copied frames.
- The title bar and controls fade out after a few seconds without pointer movement. The window resizes to the video's aspect ratio.
- Each video opens in its own window with its own playback state.
- Click the time to switch between timecode, frame number, and minutes and seconds.
- Open a video by dropping it on the window or the app icon, with Open With, or with <kbd>⌘O</kbd>.

## Install

Pluck requires **macOS 26 or later**. Grab the latest build from [Releases](https://github.com/dmccullum/Pluck/releases), or build it yourself below.

## Build from source

Double-click `build.command` to build a Release copy into `Build/Pluck.app` and open it.

Or open `Pluck.xcodeproj` in Xcode and run the `Pluck` scheme, or from Terminal:

```sh
xcodebuild -project Pluck.xcodeproj -scheme Pluck -configuration Release build
```

Pluck uses only Apple frameworks: SwiftUI, AppKit, AVFoundation, and UniformTypeIdentifiers.

## Keyboard shortcuts

| Action | Shortcut |
| --- | --- |
| Open video | <kbd>⌘O</kbd> |
| Play / pause | <kbd>Space</kbd> |
| Shuttle backward (repeat for 2×, 4×, 8×) | <kbd>J</kbd> |
| Pause | <kbd>K</kbd> |
| Shuttle forward (repeat for 2×, 4×, 8×) | <kbd>L</kbd> |
| Previous frame | <kbd>←</kbd>, <kbd>,</kbd>, or hold <kbd>K</kbd> and tap <kbd>J</kbd> |
| Next frame | <kbd>→</kbd>, <kbd>.</kbd>, or hold <kbd>K</kbd> and tap <kbd>L</kbd> |
| Jump back / forward 5 seconds | <kbd>⇧←</kbd> / <kbd>⇧→</kbd> |
| Go to start / end | <kbd>Home</kbd> / <kbd>End</kbd> |
| Save frame | <kbd>⌘S</kbd> |
| Copy frame | <kbd>⌘C</kbd> |
| Settings | <kbd>⌘,</kbd> |

Command-click the safe zone button to turn the guide on or off.

## License

[GPL-3.0](LICENSE)
