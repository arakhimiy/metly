import MetlyCore
import MetlyDesign
import SwiftUI

/// The in-app banner for a connect request that arrived while CONNECT is closed:
/// "{first} wants to connect", "{title} · {company} · {event}", Later · View · Accept.
struct IncomingRequestBanner: View {
    let item: IncomingRequestBannerItem
    let sharedCardName: String?
    let isAccepting: Bool
    let onAccept: () -> Void
    let onView: () -> Void
    let onLater: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                InitialsAvatar(name: item.peerName, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(item.firstName) wants to connect")
                        .font(.headline)
                    if !item.detail.isEmpty {
                        Text(item.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            buttons
                .controlSize(.regular)
                .disabled(isAccepting)

            if let sharedCardName {
                Text(ConnectCopy.youllShare(sharedCardName))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: 560, alignment: .leading)
        .glassOrMaterial(in: .rect(cornerRadius: 24))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .padding(.horizontal, 12)
        .gesture(
            DragGesture(minimumDistance: 12).onEnded { value in
                if value.translation.height < -24 { onLater() }   // flick up to put it off, like a notification
            }
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Connect request")
    }

    @ViewBuilder
    private var buttons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            Button(action: onLater) {
                Text("Later").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Keeps the request in People")

            Button(action: onView) {
                Text("View").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Opens your requests in People")

            Button(action: onAccept) {
                Text("Accept")
                    .opacity(isAccepting ? 0 : 1)
                    .overlay {
                        if isAccepting { ProgressView() }
                    }
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(isAccepting ? "Accepting" : "Accept \(item.firstName)’s request")
        }
    }
}

#Preview("Incoming banner") {
    VStack {
        IncomingRequestBanner(
            item: IncomingRequestBannerItem(preview: "Bekzod Tursunov", role: "Growth Lead · Alif", eventName: "Tashkent Tech Week"),
            sharedCardName: "Work", isAccepting: false, onAccept: {}, onView: {}, onLater: {})
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}

#Preview("Incoming banner · accepting, large text") {
    VStack {
        IncomingRequestBanner(
            item: IncomingRequestBannerItem(preview: "Kamila Yusupova", role: "Founder · Uzum", eventName: nil),
            sharedCardName: "Work", isAccepting: true, onAccept: {}, onView: {}, onLater: {})
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
    .environment(\.dynamicTypeSize, .accessibility2)
}

extension IncomingRequestBannerItem {
    /// Preview-only item.
    init(preview name: String, role: String, eventName: String?, method: ConnectMethod = .scan) {
        id = UUID()
        peerUserID = UUID()
        peerName = name
        self.role = role
        self.eventName = eventName
        self.method = method
    }
}
