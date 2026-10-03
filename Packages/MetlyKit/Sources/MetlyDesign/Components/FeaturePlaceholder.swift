import SwiftUI

/// Wave-0 placeholder for screens not implemented yet. Remove usages as screens land.
public struct FeaturePlaceholder: View {
    let title: String
    let specID: String

    public init(_ title: String, specID: String) {
        self.title = title
        self.specID = specID
    }

    public var body: some View {
        ContentUnavailableView(title, systemImage: "hammer", description: Text(specID))
            .navigationTitle(title)
    }
}
