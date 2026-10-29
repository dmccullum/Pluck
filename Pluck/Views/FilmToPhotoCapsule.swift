import DMKit
import SwiftUI

/// The About window's signature: film, then frames, then a photo, in one glass capsule.
/// Clicking it lights the three steps in turn, once.
struct FilmToPhotoCapsule: View {
    /// The step lit while the sequence plays (0 film, 1 frames, 2 photo), or nil at rest.
    @State private var litStep: Int?
    @State private var playback: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: play) {
            HStack(spacing: 12) {
                Image(systemName: "film.fill")
                    .foregroundStyle(Brand.skyBottom)
                    .modifier(StepEmphasis(step: 0, litStep: litStep, reduceMotion: reduceMotion))

                chevron

                HStack(spacing: 4) {
                    Image(systemName: "backward.frame.fill")
                    Image(systemName: "forward.frame.fill")
                }
                .foregroundStyle(Brand.frameBottom)
                .modifier(StepEmphasis(step: 1, litStep: litStep, reduceMotion: reduceMotion))

                chevron

                Image(systemName: "photo.fill")
                    .foregroundStyle(Brand.sunset)
                    .modifier(StepEmphasis(step: 2, litStep: litStep, reduceMotion: reduceMotion))
            }
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 19)
            .frame(height: 42)
            .floatingGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open a video, find the exact frame, and save it")
        .accessibilityHint("Plays the three steps in order")
        .accessibilityAddTraits(.isButton)
        .onDisappear { playback?.cancel() }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .foregroundStyle(.tertiary)
            .opacity(litStep == nil ? 1 : 0.5)
    }

    /// Lights film, frames and photo in turn, then returns to rest. A click mid-run starts over.
    private func play() {
        playback?.cancel()
        playback = Task {
            for step in 0..<3 {
                withDMAnimation(.spring) { litStep = step }
                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled else { return }
            }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            withDMAnimation(.smooth) { litStep = nil }
        }
    }
}

/// Dims the steps that aren't lit and lifts the lit one; under Reduce Motion only the dimming plays.
private struct StepEmphasis: ViewModifier {
    let step: Int
    let litStep: Int?
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        let isLit = litStep == step
        content
            .opacity(litStep == nil || isLit ? 1 : 0.35)
            .scaleEffect(isLit && !reduceMotion ? 1.18 : 1)
    }
}
