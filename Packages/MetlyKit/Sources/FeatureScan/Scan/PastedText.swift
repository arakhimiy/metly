import CoreTransferable
import Foundation

/// Clipboard payload for `PasteButton`: a copied link (`public.url`) or plain text
/// ("tanishly.app/c/kamila-x1y2" typed in Notes). No paste permission prompt is shown.
nonisolated struct PastedText: Transferable, Sendable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (url: URL) in PastedText(text: url.absoluteString) })
        ProxyRepresentation(importing: { (string: String) in PastedText(text: string) })
    }
}
