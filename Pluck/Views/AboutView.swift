import AppKit
import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)

            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 92, height: 92)
                .shadow(color: .black.opacity(0.32), radius: 18, y: 10)

            Text("Pluck")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .padding(.top, 12)

            workflow
                .padding(.top, 22)

            Spacer(minLength: 20)

            VStack(spacing: 4) {
                Text(versionText)
                    .foregroundStyle(.secondary)

                Text("Made with love by Daniel McCullum")
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.bottom, 26)
        }
        .frame(width: 420, height: 350)
        .foregroundStyle(.white)
        .containerBackground(for: .window) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.105, green: 0.12, blue: 0.22),
                        Color(red: 0.10, green: 0.16, blue: 0.22),
                        Color(red: 0.19, green: 0.14, blue: 0.20)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                RadialGradient(
                    colors: [Brand.skyBottom.opacity(0.28), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 330
                )
            }
        }
        .windowMinimizeBehavior(.disabled)
    }

    private var workflow: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.fill")
                .foregroundStyle(Brand.skyTop)

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)

            HStack(spacing: 4) {
                Image(systemName: "backward.frame.fill")
                Image(systemName: "forward.frame.fill")
            }
            .foregroundStyle(Brand.frameTop)

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)

            Image(systemName: "photo.fill")
                .foregroundStyle(Brand.sunset)
        }
        .font(.system(size: 15, weight: .semibold))
        .padding(.horizontal, 19)
        .frame(height: 42)
        .glassEffect(
            .regular.tint(Brand.skyBottom.opacity(0.12)),
            in: .capsule
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open a video, find the exact frame, and save it")
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }
}
