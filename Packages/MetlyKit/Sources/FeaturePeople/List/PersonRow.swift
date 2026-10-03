import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// What the third line of a person row shows.
enum PersonRowMeta {
    /// "{via} · {event or place} · {when}" (All / Tags).
    case event
    /// "{event}, {date}" (Places).
    case eventAndDate
}

/// People list row: avatar, name (+ "via web" badge / merged icon), role and meeting meta.
struct PersonRow: View {
    let person: Connection
    var meta: PersonRowMeta = .event

    var body: some View {
        HStack(spacing: 12) {
            InitialsAvatar(name: person.fullName, imageData: person.avatarData, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(person.fullName)
                        .font(.headline)
                        .lineLimit(1)
                    if person.isMerged {
                        Image(systemName: "arrow.triangle.merge")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Merged")
                    }
                    if person.source == .webShareBack {
                        ViaWebBadge()
                    }
                }
                if !role.isEmpty {
                    Text(role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let metaText {
                    Text(metaText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var role: String {
        [person.jobTitle, person.company].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var metaText: String? {
        let context = person.context
        let when = context.metAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
        switch meta {
        case .event:
            let via: String? = switch person.source {
            case .justMet, .scanQR, .paper: person.source.viaLabel
            default: nil
            }
            let whereMet = context.eventName ?? context.place
            return [via, whereMet, when].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        case .eventAndDate:
            let date = context.metAt.formatted(.dateTime.month(.abbreviated).day())
            let whereMet = context.eventName ?? context.place ?? ""
            return whereMet.isEmpty ? date : "\(whereMet), \(date)"
        }
    }
}

/// "via web" capsule for web share-backs.
struct ViaWebBadge: View {
    var body: some View {
        Label("via web", systemImage: "globe")
            .font(.caption.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.tint.opacity(0.12), in: .capsule)
            .labelStyle(.titleAndIcon)
            .fixedSize()
    }
}

/// Grey placeholder used by the loading skeleton.
struct PersonRowPlaceholder: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.quaternary)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Placeholder Name")
                    .font(.headline)
                Text("Product Designer · Company")
                    .font(.subheadline)
                Text("Event · 2d ago")
                    .font(.footnote)
            }
        }
        .padding(.vertical, 2)
        .redacted(reason: .placeholder)
    }
}
