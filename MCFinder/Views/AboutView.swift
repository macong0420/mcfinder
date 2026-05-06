import SwiftUI

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 80, height: 80)
            } else {
                Image(systemName: "magnifyingglass.circle.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.accentColor)
            }

            Text("MCFinder")
                .font(.title)
                .fontWeight(.bold)

            Text("Version 1.0.0")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Find any file, instantly.")
                .font(.body)
                .foregroundColor(.secondary)

            Divider().frame(width: 200)

            HStack(spacing: 16) {
                Link("Help", destination: URL(string: "https://mcfinder.app/help")!)
                Link("Privacy", destination: URL(string: "https://mcfinder.app/privacy")!)
                Link("Terms", destination: URL(string: "https://mcfinder.app/terms")!)
            }

            Text("Copyright (c) 2026 MCFinder. All rights reserved.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(32)
    }
}
