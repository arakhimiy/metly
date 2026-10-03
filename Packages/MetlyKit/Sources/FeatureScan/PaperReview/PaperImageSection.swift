import MetlyDesign
import SwiftUI

/// The captured photo with "{N} fields found", and Retake.
struct PaperImageSection: View {
    let imageData: Data
    let detectedCount: Int
    let onRetake: () -> Void

    var body: some View {
        Section {
            if let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        if detectedCount > 0 {
                            Text("^[\(detectedCount) field](inflect: true) found")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .glassOrMaterial(in: .capsule)
                                .padding(10)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 240)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Photo of the business card")
                    .accessibilityValue(detectedCount > 0 ? "\(detectedCount) fields found" : "")
            }
            Button("Retake Photo", systemImage: "camera", action: onRetake)
        }
    }
}
