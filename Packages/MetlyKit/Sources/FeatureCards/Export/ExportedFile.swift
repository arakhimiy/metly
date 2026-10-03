import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// A rendered PDF handed to `fileExporter` ("Save to Files").
nonisolated struct ExportedPDF: Transferable, Sendable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
    }
}
