import MetlyCore
import MetlyData
import MetlyDesign
import PhotosUI
import SwiftUI

/// Profile photo with a camera badge. Tap picks a photo (`PhotosPicker`, no library permission
/// needed), then "Move and Scale"; with a photo set, a menu also offers "Remove Photo". Stored downscaled in `profile.photoData`.
struct AvatarPickerButton: View {
    let profile: Profile
    @Environment(AppRouter.self) private var router
    @ScaledMetric(relativeTo: .title) private var size = 72.0
    @State private var isPickerPresented = false
    @State private var selection: PhotosPickerItem?
    @State private var isProcessing = false
    @State private var cropItem: CropImage?

    var body: some View {
        Group {
            if profile.photoData == nil {
                Button(action: choosePhoto) {
                    EditableAvatar(name: profile.fullName, photoData: nil, size: size, isProcessing: isProcessing)
                }
            } else {
                Menu {
                    Button("Choose Photo…", systemImage: "photo.on.rectangle", action: choosePhoto)
                    Button("Remove Photo", systemImage: "trash", role: .destructive, action: removePhoto)
                } label: {
                    EditableAvatar(name: profile.fullName, photoData: profile.photoData, size: size, isProcessing: isProcessing)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .photosPicker(isPresented: $isPickerPresented, selection: $selection, matching: .images)
        .onChange(of: selection) { _, item in
            guard let item else { return }
            Task { await loadPhoto(from: item) }
        }
        .imageCropper(item: $cropItem) { cropped in
            Task { await savePhoto(cropped) }
        }
        .accessibilityLabel("Profile Photo")
        .accessibilityHint(profile.photoData == nil ? "Choose a photo" : "Change or remove your photo")
    }

    private func choosePhoto() {
        isPickerPresented = true
    }

    private func removePhoto() {
        profile.photoData = nil
        profile.markChanged()
    }

    /// Picked photo → "Move and Scale" → `savePhoto`.
    private func loadPhoto(from item: PhotosPickerItem) async {
        isProcessing = true
        defer {
            isProcessing = false
            selection = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let crop = await CropImage.load(data) else {
            showLoadError()
            return
        }
        cropItem = crop
    }

    private func savePhoto(_ cropped: Data) async {
        isProcessing = true
        defer { isProcessing = false }
        guard let jpeg = await ImageDownscaler.jpegData(from: cropped) else {
            showLoadError()
            return
        }
        profile.photoData = jpeg
        profile.markChanged()
    }

    private func showLoadError() {
        router.showToast(String(localized: "Couldn’t Load Photo", bundle: .appStrings), systemImage: "exclamationmark.triangle")
    }
}

/// Avatar circle with the camera badge and a loading veil.
private struct EditableAvatar: View {
    let name: String
    let photoData: Data?
    let size: Double
    let isProcessing: Bool

    var body: some View {
        InitialsAvatar(name: name, imageData: photoData, size: size)
            .overlay {
                if isProcessing {
                    Circle().fill(.black.opacity(0.4))
                    ProgressView().tint(.white)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "camera.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color.accentColor, in: .circle)
                    .overlay { Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2) }
                    .accessibilityHidden(true)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.circle)
    }
}
