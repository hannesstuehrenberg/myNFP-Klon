import Foundation
import Compression

/// Minimaler ZIP-Schreiber (Methode „stored“, ohne Kompression) – genügt für Export-Archive.
public struct ZipWriter {
    private var entries: [(name: String, data: Data)] = []

    public init() {}

    public mutating func add(_ name: String, data: Data) {
        entries.append((name, data))
    }

    public mutating func add(_ name: String, text: String) {
        add(name, data: Data(text.utf8))
    }

    public func build(date: Date = Date()) -> Data {
        var out = Data()
        var central = Data()
        let (dosTime, dosDate) = Self.dosDateTime(date)
        for e in entries {
            let nameData = Data(e.name.utf8)
            let crc = CRC32.checksum(e.data)
            let offset = UInt32(out.count)
            // Local file header
            out.appendLE(UInt32(0x04034b50))
            out.appendLE(UInt16(20))          // version needed
            out.appendLE(UInt16(0x0800))      // flags: UTF-8
            out.appendLE(UInt16(0))           // method: stored
            out.appendLE(dosTime)
            out.appendLE(dosDate)
            out.appendLE(crc)
            out.appendLE(UInt32(e.data.count))
            out.appendLE(UInt32(e.data.count))
            out.appendLE(UInt16(nameData.count))
            out.appendLE(UInt16(0))
            out.append(nameData)
            out.append(e.data)
            // Central directory
            central.appendLE(UInt32(0x02014b50))
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(20))
            central.appendLE(UInt16(0x0800))
            central.appendLE(UInt16(0))
            central.appendLE(dosTime)
            central.appendLE(dosDate)
            central.appendLE(crc)
            central.appendLE(UInt32(e.data.count))
            central.appendLE(UInt32(e.data.count))
            central.appendLE(UInt16(nameData.count))
            central.appendLE(UInt16(0))   // extra
            central.appendLE(UInt16(0))   // comment
            central.appendLE(UInt16(0))   // disk
            central.appendLE(UInt16(0))   // internal attrs
            central.appendLE(UInt32(0))   // external attrs
            central.appendLE(offset)
            central.append(nameData)
        }
        let centralOffset = UInt32(out.count)
        out.append(central)
        out.appendLE(UInt32(0x06054b50))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(0))
        out.appendLE(UInt16(entries.count))
        out.appendLE(UInt16(entries.count))
        out.appendLE(UInt32(central.count))
        out.appendLE(centralOffset)
        out.appendLE(UInt16(0))
        return out
    }

    static func dosDateTime(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let hour: Int = c.hour ?? 0, minute: Int = c.minute ?? 0, second: Int = c.second ?? 0
        let year: Int = max(0, (c.year ?? 1980) - 1980), month: Int = c.month ?? 1, day: Int = c.day ?? 1
        let time: Int = (hour << 11) | (minute << 5) | (second / 2)
        let date: Int = (year << 9) | (month << 5) | day
        return (UInt16(truncatingIfNeeded: time), UInt16(truncatingIfNeeded: date))
    }
}

/// Minimaler ZIP-Leser (Methoden „stored“ und „deflate“).
public enum ZipReader {
    public enum ZipError: LocalizedError {
        case invalidArchive
        case unsupportedMethod
        public var errorDescription: String? {
            switch self {
            case .invalidArchive: return "Ungültiges ZIP-Archiv."
            case .unsupportedMethod: return "Nicht unterstützte ZIP-Kompression."
            }
        }
    }

    public static func isZip(_ data: Data) -> Bool {
        data.count >= 4 && data.readLE32(at: 0) == 0x04034b50
    }

    public static func entries(_ data: Data) throws -> [String: Data] {
        // End of central directory suchen
        guard data.count >= 22 else { throw ZipError.invalidArchive }
        var eocd = -1
        var i = data.count - 22
        while i >= max(0, data.count - 65557) {
            if data.readLE32(at: i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.invalidArchive }
        let count = Int(data.readLE16(at: eocd + 10))
        var p = Int(data.readLE32(at: eocd + 16))
        var result: [String: Data] = [:]
        for _ in 0..<count {
            guard p + 46 <= data.count, data.readLE32(at: p) == 0x02014b50 else { throw ZipError.invalidArchive }
            let method = data.readLE16(at: p + 10)
            let compSize = Int(data.readLE32(at: p + 20))
            let size = Int(data.readLE32(at: p + 24))
            let nameLen = Int(data.readLE16(at: p + 28))
            let extraLen = Int(data.readLE16(at: p + 30))
            let commentLen = Int(data.readLE16(at: p + 32))
            let localOffset = Int(data.readLE32(at: p + 42))
            let name = String(decoding: data.subdata(in: (p + 46)..<(p + 46 + nameLen)), as: UTF8.self)
            p += 46 + nameLen + extraLen + commentLen

            guard localOffset + 30 <= data.count else { throw ZipError.invalidArchive }
            let lNameLen = Int(data.readLE16(at: localOffset + 26))
            let lExtraLen = Int(data.readLE16(at: localOffset + 28))
            let start = localOffset + 30 + lNameLen + lExtraLen
            guard start + compSize <= data.count else { throw ZipError.invalidArchive }
            let raw = data.subdata(in: start..<(start + compSize))
            switch method {
            case 0: result[name] = raw
            case 8: result[name] = try inflate(raw, expectedSize: size)
            default: throw ZipError.unsupportedMethod
            }
        }
        return result
    }

    static func inflate(_ data: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        var out = Data(count: expectedSize)
        let written = out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                compression_decode_buffer(dst.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                                          src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw ZipError.invalidArchive }
        return out
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in data { crc = table[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}

extension Data {
    mutating func appendLE(_ v: UInt16) { var x = v.littleEndian; Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) } }
    mutating func appendLE(_ v: UInt32) { var x = v.littleEndian; Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) } }
    func readLE16(at i: Int) -> UInt16 {
        guard i + 2 <= count else { return 0 }
        let s = startIndex + i
        return UInt16(self[s]) | UInt16(self[s + 1]) << 8
    }
    func readLE32(at i: Int) -> UInt32 {
        guard i + 4 <= count else { return 0 }
        let s = startIndex + i
        return UInt32(self[s]) | UInt32(self[s + 1]) << 8 | UInt32(self[s + 2]) << 16 | UInt32(self[s + 3]) << 24
    }
}
