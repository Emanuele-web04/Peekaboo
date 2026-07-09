import AppKit
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct TaskDragPayload: Codable, Sendable, Transferable {
    let id: UUID
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .peekabooTask)
        ProxyRepresentation(exporting: \.title)
    }

    func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.peekabooTask.identifier,
            visibility: .ownProcess
        ) { completion in
            do {
                completion(try JSONEncoder().encode(self), nil)
            } catch {
                completion(nil, error)
            }
            return nil
        }
        let plainTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let inlineHTML = "<span>\(plainTitle.htmlEscaped)</span>"
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.html.identifier,
            visibility: .all
        ) { completion in
            completion(Data(inlineHTML.utf8), nil)
            return nil
        }
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

private extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

extension UTType {
    static let peekabooTask = UTType(exportedAs: "com.emanueledipietro.peekaboo.task")
}

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case todo
    case inProgress
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todo: "To do"
        case .inProgress: "In Progress"
        case .done: "Done"
        }
    }
}

enum TaskPriority: String, Codable, CaseIterable, Identifiable {
    case none
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var shortLabel: String {
        switch self {
        case .none: "–"
        case .low: "L"
        case .medium: "M"
        case .high: "H"
        }
    }

    var sortRank: Int {
        switch self {
        case .none: -1
        case .low: 0
        case .medium: 1
        case .high: 2
        }
    }
}

enum ScreenCorner: String, Codable, CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}
