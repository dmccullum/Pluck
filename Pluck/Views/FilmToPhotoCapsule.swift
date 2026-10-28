import DMKit
import SwiftUI

/// The About window's signature: film, then frames, then a photo, in one glass capsule.
struct FilmToPhotoCapsule: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.fill")
                .foregroundStyle(Brand.skyBottom)

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)

            HStack(spacing: 4) {
                Image(systemName: "backward.frame.fill")
                Image(systemName: "forward.frame.fill")
            }
            .foregroundStyle(Brand.frameBottom)

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)

            Image(systemName: "photo.fill")
                .foregroundStyle(Brand.sunset)
        }
        .font(.title3.weight(.semibold))
        .padding(.horizontal, 19)
        .frame(height: 42)
        .floatingGlass(in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open a video, find the exact frame, and save it")
    }
}
