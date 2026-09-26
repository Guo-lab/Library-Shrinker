import SwiftUI

enum ShrinkerMode: String, CaseIterable, Identifiable {
    case video
    case image

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .video: "Video Shrinker"
        case .image: "Image Shrinker"
        }
    }

    var iconName: String {
        switch self {
        case .video: "video"
        case .image: "photo"
        }
    }
}

struct ContentView: View {
    @State private var mode: ShrinkerMode = .video

    var body: some View {
        switch mode {
        case .video:
            VideoShrinkerView(mode: $mode)
        case .image:
            ImageShrinkerView(mode: $mode)
        }
    }
}

struct ShrinkerModeMenu: View {
    @Binding var mode: ShrinkerMode
    @State private var isChoosingMode = false

    var body: some View {
        Button {
            isChoosingMode = true
        } label: {
            HStack(spacing: 5) {
                Text(mode.title)
                    .font(.headline)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose shrinker")
        .confirmationDialog(
            "Choose Shrinker",
            isPresented: $isChoosingMode,
            titleVisibility: .visible
        ) {
            ForEach(ShrinkerMode.allCases) { option in
                Button {
                    mode = option
                } label: {
                    Label(option.title, systemImage: option.iconName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
