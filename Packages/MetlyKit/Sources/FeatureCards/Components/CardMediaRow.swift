import PhotosUI
import SwiftUI

/// One "Show on This Card" row for the profile photo or logo: thumbnail, title, and the card's switch.
/// Without an image the row offers "Add…" (PhotosPicker); with one, the thumbnail opens Change / Remove.
/// A picked image is downscaled (logos also trimmed) off the main actor and kept as a `MediaEdit` until
/// the card is saved; picking one switches it on for this card.
struct CardMediaRow: View {
    let kind: MediaKind
    /// The image currently in effect (profile value with the pending edit applied).
    let imageData: Data?
    @Binding var edit: MediaEdit
    @Binding var isOn: Bool

    @State private var pickerItem: PhotosPickerItem?
    @State private var isPickerPresented = false
    @State private var isLoading = false
    @State private var isShowingLoadError = false

    var body: some View {
        HStack(spacing: 14) {
            if imageData == nil {
                Button { isPickerPresented = true } label: { addLabel }
                    .buttonStyle(.plain)
            } else {
                Menu {
                    Button(kind.changeTitle, systemImage: "photo.on.rectangle") { isPickerPresented = true }
                    Button(kind.removeTitle, systemImage: "trash", role: .destructive) { edit = .removed }
                } label: {
                    HStack(spacing: 14) {
                        MediaThumbnail(kind: kind, imageData: imageData)
                        Text(kind.title).foregroundStyle(Color.primary)
                    }
                }
                Spacer(minLength: 8)
                Toggle(kind.title, isOn: $isOn).labelsHidden()
            }
            if isLoading { ProgressView() }
        }
        .photosPicker(isPresented: $isPickerPresented, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await load(item) }
        }
        .alert("Couldn’t Use This Image", isPresented: $isShowingLoadError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try a different photo.")
        }
        .disabled(isLoading)
    }

    private var addLabel: some View {
        HStack(spacing: 14) {
            MediaThumbnail(kind: kind, imageData: nil)
            Text(kind.chooseTitle).foregroundStyle(Color.accentColor)
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }

    private func load(_ item: PhotosPickerItem) async {
        isLoading = true
        defer {
            isLoading = false
            pickerItem = nil   // so picking the same image again triggers onChange
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let scaled = await ImageDownscaler.downscale(data, maxPixelSize: kind.maxPixelSize, format: kind.format,
                                                           trimsMargins: kind == .logo)
        else {
            isShowingLoadError = true
            return
        }
        edit = .replaced(scaled)
        isOn = true
    }
}

enum MediaKind {
    case photo, logo

    var title: String {
        switch self {
        case .photo: String(localized: "Photo", bundle: .appStrings)
        case .logo: String(localized: "Logo", bundle: .appStrings)
        }
    }

    var chooseTitle: String {
        switch self {
        case .photo: String(localized: "Add Photo…", bundle: .appStrings)
        case .logo: String(localized: "Add Logo…", bundle: .appStrings)
        }
    }

    var changeTitle: String {
        switch self {
        case .photo: String(localized: "Change Photo…", bundle: .appStrings)
        case .logo: String(localized: "Change Logo…", bundle: .appStrings)
        }
    }

    var removeTitle: String {
        switch self {
        case .photo: String(localized: "Remove Photo", bundle: .appStrings)
        case .logo: String(localized: "Remove Logo", bundle: .appStrings)
        }
    }

    var maxPixelSize: Int {
        switch self {
        case .photo: 640
        case .logo: 1024
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
                if kind == .logo {
                    // Logos are never cropped; they sit on a neutral tile.
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(5)
                        .background(Color(.tertiarySystemFill))
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
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
