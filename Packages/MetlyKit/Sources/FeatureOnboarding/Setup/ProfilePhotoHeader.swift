import MetlyDesign
import PhotosUI
import SwiftUI

/// Circular photo preview + "Add Photo" picker + the screen's explanation line.
struct ProfilePhotoHeader: View {
    let name: String
    let photoData: Data?
    @Binding var selection: PhotosPickerItem?
    let isProcessing: Bool
    let onRemove: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var size = 96.0

    var body: some View {
        // Built outside the picker's (Sendable) label closure.
        let avatar = ProfileAvatar(name: name, photoData: photoData, isProcessing: isProcessing, size: size)

        VStack(spacing: 12) {
            PhotosPicker(selection: $selection, matching: .images) {
                avatar
            }
            .buttonStyle(.plain)
            // The text button below is the accessible control; this is a larger visual target.
            .accessibilityHidden(true)

            PhotosPicker(photoData == nil ? "Add Photo" : "Change Photo", selection: $selection, matching: .images)
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)

            Text("This fills in your cards. You can change it anytime.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .contextMenu {
            if photoData != nil {
                Button("Remove Photo", systemImage: "trash", role: .destructive, action: onRemove)
            }
        }
    }
}

/// Photo, initials, or a placeholder symbol — with a camera badge and a processing spinner.
private struct ProfileAvatar: View {
    let name: String
    let photoData: Data?
    let isProcessing: Bool
    let size: Double

    var body: some View {
        Group {
            if photoData != nil || !name.trimmingCharacters(in: .whitespaces).isEmpty {
                InitialsAvatar(name: name, imageData: photoData, size: size)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        }
        .overlay {
            if isProcessing {
                ProgressView()
                    .frame(width: size, height: size)
                    .background(.ultraThinMaterial, in: .circle)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "camera.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(7)
                .background(Color.accentColor, in: .circle)
                .overlay { Circle().stroke(Color(.systemGroupedBackground), lineWidth: 2) }
        }
    }
}
