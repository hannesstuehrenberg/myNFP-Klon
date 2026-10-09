import Foundation

/// Eine Zeile im Auswertungsprotokoll („Wie wurde ausgewertet?“)
public struct ProtocolEntry: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case info, rule, warning, result
    }

    public let id = UUID()
    public let kind: Kind
    public let text: String

    public init(kind: Kind, text: String) {
        self.kind = kind
        self.text = text
    }

    public static func info(_ t: String) -> ProtocolEntry { .init(kind: .info, text: t) }
    public static func rule(_ t: String) -> ProtocolEntry { .init(kind: .rule, text: t) }
    public static func warning(_ t: String) -> ProtocolEntry { .init(kind: .warning, text: t) }
    public static func result(_ t: String) -> ProtocolEntry { .init(kind: .result, text: t) }

    public static func == (l: ProtocolEntry, r: ProtocolEntry) -> Bool { l.kind == r.kind && l.text == r.text }
    public func hash(into h: inout Hasher) { h.combine(kind); h.combine(text) }
}
