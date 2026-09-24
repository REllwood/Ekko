import AppKit
import Foundation

/// A copy of every item/type currently on a pasteboard, so Ekko can put the user's clipboard back
/// after pasting the transcript.
struct PasteboardSnapshot: Sendable, Equatable {
    struct Item: Sendable, Equatable {
        /// Raw pasteboard-type string -> data.
        var contents: [String: Data]
    }

    var items: [Item]

    init(items: [Item] = []) {
        self.items = items
    }

    var isEmpty: Bool { items.allSatisfy { $0.contents.isEmpty } }

    @MainActor
    static func capture(from pasteboard: NSPasteboard = .general) -> PasteboardSnapshot {
        var items: [Item] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var contents: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type.rawValue] = data
                }
            }
            if !contents.isEmpty { items.append(Item(contents: contents)) }
        }
        return PasteboardSnapshot(items: items)
    }

    @MainActor
    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored: [NSPasteboardItem] = items.map { item in
            let pasteboardItem = NSPasteboardItem()
            for (type, data) in item.contents {
                pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return pasteboardItem
        }
        pasteboard.writeObjects(restored)
    }
}
