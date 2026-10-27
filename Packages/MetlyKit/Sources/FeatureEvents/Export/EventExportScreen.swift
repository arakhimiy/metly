import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// EVENT_EXPORT (SPEC §2.5.36) — CSV only in v1 (PLAN: no CRM integrations). Large sheet.
struct EventExportScreen: View {
    @Query private var matches: [Event]
    @Environment(AppRouter.self) private var router

    init(eventID: UUID) {
        let id = eventID
        _matches = Query(filter: #Predicate<Event> { $0.id == id })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let event = matches.first, !event.isDeleted {
                    EventExportContent(event: event)
                } else {
                    ContentUnavailableView("Event Not Found", systemImage: "calendar.badge.exclamationmark",
                                           description: Text("This event may have been removed."))
                }
            }
            .navigationTitle(matches.first?.name ?? String(localized: "Export"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: router.dismiss)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct EventExportContent: View {
    let event: Event

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services

    @Query(Connection.live) private var people: [Connection]

    @State private var options = EventCSVColumn.allCases.map { ExportColumnOption(column: $0) }
    @State private var fileURL: URL?
    @State private var writeFailed = false

    var body: some View {
        let rows = EventMembership.members(of: event, among: people)
            .map { EventCSVRow(person: $0, eventName: event.name) }
        let columns = EventCSVColumn.ordered(options.filter(\.isIncluded).map(\.column))
        Form {
            ExportSummarySection(peopleCount: rows.count)
            if rows.isEmpty {
                ContentUnavailableView("No One to Export", systemImage: "person.2",
                                       description: Text("People you meet at this event will appear here."))
            } else {
                CSVPreviewSection(rows: rows, columns: columns)
            }
            ExportFieldsSection(options: $options)
        }
        .bottomActionBar {
            ExportCallToAction(isPro: services.entitlements.isPro, peopleCount: rows.count,
                               fileURL: fileURL, eventName: event.name, writeFailed: writeFailed,
                               onUpgrade: upgrade)
        }
        .task(id: ExportSnapshot(rows: rows, columns: columns)) {
            write(rows: rows, columns: columns)
        }
        .onDisappear(perform: EventCSV.removeExports)
    }

    private func write(rows: [EventCSVRow], columns: [EventCSVColumn]) {
        guard !rows.isEmpty else {
            fileURL = nil
            return
        }
        do {
            fileURL = try EventCSV.write(rows: rows, columns: columns, eventName: event.name)
            writeFailed = false
        } catch {
            fileURL = nil
            writeFailed = true
        }
    }

    private func upgrade() {
        router.present(.paywall(trigger: .eventExport))
    }
}

/// Re-generates the file whenever the people or the chosen columns change.
private struct ExportSnapshot: Equatable {
    let rows: [EventCSVRow]
    let columns: [EventCSVColumn]
}

/// One "Included" toggle.
struct ExportColumnOption: Identifiable, Equatable {
    let column: EventCSVColumn
    var isIncluded = true

    var id: EventCSVColumn { column }
}
