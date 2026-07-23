import Foundation

enum LogReadError: Error {
    case invalidRootObject
}

enum JSONLineReader {
    static func forEachObject(at url: URL, body: ([String: Any], Int) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var pending = Data()
        var lineNumber = 0

        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { break }
            pending.append(chunk)

            while let newline = pending.firstIndex(of: 0x0A) {
                let line = pending[..<newline]
                pending.removeSubrange(...newline)
                lineNumber += 1
                try decode(line: Data(line), lineNumber: lineNumber, body: body)
            }
        }

        if !pending.isEmpty {
            lineNumber += 1
            try decode(line: pending, lineNumber: lineNumber, body: body)
        }
    }

    private static func decode(
        line: Data,
        lineNumber: Int,
        body: ([String: Any], Int) throws -> Void
    ) throws {
        guard !line.isEmpty else { return }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        try body(object, lineNumber)
    }
}

extension Dictionary where Key == String, Value == Any {
    func dictionary(_ key: String) -> [String: Any]? {
        self[key] as? [String: Any]
    }

    func string(_ key: String) -> String? {
        self[key] as? String
    }

    func int64(_ key: String) -> Int64 {
        if let number = self[key] as? NSNumber { return number.int64Value }
        if let value = self[key] as? String, let number = Int64(value) { return number }
        return 0
    }

    func double(_ key: String) -> Double? {
        if let number = self[key] as? NSNumber { return number.doubleValue }
        if let value = self[key] as? String { return Double(value) }
        return nil
    }
}

enum LogDateParser {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter = ISO8601DateFormatter()

    static func parse(_ value: Any?) -> Date? {
        if let string = value as? String {
            return fractionalFormatter.date(from: string) ?? standardFormatter.date(from: string)
        }

        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
        }

        return nil
    }
}

