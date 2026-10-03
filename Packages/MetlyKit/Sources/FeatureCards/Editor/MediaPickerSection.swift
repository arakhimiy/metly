import PhotosUI
import SwiftUI

/// Photo or logo picker rows: thumbnail + "Choose…", "Remove…", and the card's "Show on Card" switch.
/// Picked images are downscaled off the main actor and kept in the draft until Done.
struct MediaPickerSection: View {
    let kind: MediaKind
    /// The image currently in effect (profile value with the draft's edit applied).
    let imageData: Data?
    @Binding var edit: MediaEdit
    @Binding var showOnCard: Bool
    /// e.g. "Your current template doesn't show a photo."
    let note: String?

    @State private var pickerItem: PhotosPickerItem?
    @State private var isLoading = false
    @State private var isShowingLoadError = false

    var body: some View {
        // Built outside the picker's (nonisolated) label closure.
        let label = MediaPickerLabel(kind: kind, imageData: imageData, isLoading: isLoading)
        Section {
            PhotosPicker(selection: $pickerItem, matching: .images) { label }
                .disabled(isLoading)

            if imageData != nil {
                Button(kind.removeTitle, role: .destructive) { edit = .removed }
            }

            Toggle("Show on Card", isOn: $showOnCard)
        } header: {
            Text(kind.title)
        } footer: {
            Text([kind.footer, note].compactMap(\.self).joined(separator: " "))
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .alert("Couldn’t Use This Image", isPresented: $isShowingLoadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try a different photo.")
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        isLoading = true
        defer {
            isLoading = false
            pickerItem = nil   // so picking the same image again triggers onChange
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let scaled = await ImageDownscaler.downscale(data, maxPixelSize: kind.maxPixelSize, format: kind.format)
        else {
            isShowingLoadError = true
            return
        }
        edit = .replaced(scaled)
    }
}

/// Thumbnail + "Choose Photo…" (+ spinner while a picked image is processed).
private struct MediaPickerLabel: View {
    let kind: MediaKind
    let imageData: Data?
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 14) {
            MediaThumbnail(kind: kind, imageData: imageData)
            Text(kind.chooseTitle)
            Spacer(minLength: 0)
            if isLoading { ProgressView() }
        }
        .contentShape(.rect)
    }
}

/// Profile-level images edited from the card editor.
enum MediaKind {
    case photo, logo

    var title: String {
        switch self {
        case .photo: "Photo"
        case .logo: "Logo"
        }
    }

    var chooseTitle: String {
        switch self {
        case .photo: "Choose Photo…"
        case .logo: "Choose Logo…"
        }
    }

    var removeTitle: String {
        switch self {
        case .photo: "Remove Photo"
        case .logo: "Remove Logo"
        }
    }

    var footer: String {
        switch self {
        case .photo: "Shows on Modern, Split and Stack. Your photo is shared by all your cards."
        case .logo: "Shows on Professional. Your logo is shared by all your cards."
        }
    }

    var maxPixelSize: Int {
        switch self {
        case .photo: 640
        case .logo: 512
        }
    }

    var format: ImageDownscaler.Format {
        switch self {
        case .photo: .jpeg(quality: 0.8)
        case .logo: .png
        }
    }

    var placeholderSymbol: String {
        switch self {
        case .photo: "person.crop.circle.fill"
        case .logo: "building.2.crop.circle.fill"
        }
    }
}

/// Small round (photo) or rounded-square (logo) preview, or a placeholder symbol.
struct MediaThumbnail: View {
    let kind: MediaKind
    let imageData: Data?
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 44

    var body: some View {
        Group {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: kind.placeholderSymbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(kind == .photo ? AnyShape(.circle) : AnyShape(.rect(cornerRadius: 8)))
        .accessibilityHidden(true)
    }
}
