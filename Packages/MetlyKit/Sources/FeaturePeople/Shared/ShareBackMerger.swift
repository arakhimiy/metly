import Foundation
import MetlyCore
import MetlyData
import SwiftData

/// Matching and merging a web share-back into a "Who did you just meet?" record (SPEC §3.8, PLAN Q18).
/// Never automatic: ADD_CONTEXT asks "Is this who you met at 14:32?" and merges only on confirmation.
enum ShareBackMerger {
    /// Pending just-met records that could be this share-back: same calendar day and the same first name
    /// (case/diacritic-insensitive), or saved without a name. Name matches first, then closest in time.
    static func candidates(for shareBack: Connection, among people: [Connection],
                           calendar: Calendar = .current) -> [Connection] {
        guard shareBack.source == .webShareBack, !shareBack.isMerged, !shareBack.isDeleted else { return [] }
        let reference = shareBack.createdAt
        let matches = people.filter { candidate in
            candidate.id != shareBack.id
                && candidate.isPendingMerge && !candidate.isMerged
                && !candidate.isDeleted && !candidate.isBlocked
                && calendar.isDate(candidate.context.metAt, inSameDayAs: reference)
                && (PersonName.firstNamesMatch(candidate.fullName, shareBack.fullName)
                    || JustMetNaming.isPlaceholder(candidate.fullName))
        }
        return matches.sorted { lhs, rhs in
            let lhsName = PersonName.firstNamesMatch(lhs.fullName, shareBack.fullName)
            let rhsName = PersonName.firstNamesMatch(rhs.fullName, shareBack.fullName)
            if lhsName != rhsName { return lhsName }
            return abs(lhs.context.metAt.timeIntervalSince(reference)) < abs(rhs.context.metAt.timeIntervalSince(reference))
        }
    }

    /// Copies what the share-back knows into the just-met record (keeping the owner's note and context),
    /// marks it merged and soft-deletes the duplicate. Saves the context.
    static func merge(_ shareBack: Connection, into justMet: Connection, in context: ModelContext) {
        if JustMetNaming.isPlaceholder(justMet.fullName)
            || shareBack.fullName.split(separator: " ").count > justMet.fullName.split(separator: " ").count {
            justMet.fullName = shareBack.fullName
        }
        for kind in ContactFieldKind.allCases where kind != .phone && justMet.value(for: kind).isEmpty {
            justMet.setValue(shareBack.value(for: kind), for: kind)
        }
        // Their numbers with their labels: fills the just-met record's gaps, never overwrites a number.
        justMet.mergeContacts(shareBack.contacts)
        if justMet.jobTitle.isEmpty { justMet.jobTitle = shareBack.jobTitle }
        if justMet.company.isEmpty { justMet.company = shareBack.company }
        if justMet.remoteUserID == nil { justMet.remoteUserID = shareBack.remoteUserID }
        if justMet.theirCard == nil { justMet.theirCard = shareBack.theirCard }
        if justMet.avatarData == nil { justMet.avatarData = shareBack.avatarData }

        let extraNote = shareBack.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extraNote.isEmpty {
            justMet.note = justMet.note.isEmpty ? extraNote : justMet.note + "\n\n" + extraNote
        }
        for tag in shareBack.tags where !justMet.tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            justMet.tags.append(tag)
        }

        // One open reminder per person: keep the just-met one, otherwise adopt the share-back's.
        let theirOpen = shareBack.followUps.filter { !$0.isDone && !$0.isDeleted }
        if justMet.openFollowUp == nil, let adopted = theirOpen.first {
            adopted.connection = justMet
            adopted.markChanged()
            theirOpen.dropFirst().forEach { $0.markDeleted() }
        } else {
            theirOpen.forEach { $0.markDeleted() }
        }

        justMet.isMerged = true
        justMet.isPendingMerge = false
        justMet.markChanged()
        shareBack.markDeleted()
        try? context.save()
    }
}
