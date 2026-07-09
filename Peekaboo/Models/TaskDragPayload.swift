import AppKit
import Foundation
import UniformTypeIdentifiers

struct TaskDragPayload: Sendable {
    let title: String

    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        let plainTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.utf8PlainText.identifier,
            visibility: .all
        ) { completion in
            completion(Data(plainTitle.utf8), nil)
            return nil
        }
        return provider
    }
}
