import Foundation

// MARK: - Response Handling

/// Result of checking response data type
public enum ResponseType: Equatable {
    case json(String)
    case text(String)
    case binary(Data)
}

/// Determine response type and format if possible
public func classifyResponse(_ data: Data) -> ResponseType {
    // Try to parse as JSON and re-serialize with pretty printing
    if let json = try? JSONSerialization.jsonObject(with: data),
       let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
       let prettyString = String(data: prettyData, encoding: .utf8)
    {
        return .json(prettyString)
    }

    // Try as plain text
    if let text = String(data: data, encoding: .utf8) {
        // Check if it looks like valid text (not binary garbage)
        let nonPrintableCount: Int = text.unicodeScalars.filter { scalar in
            // Allow printable ASCII, newlines, tabs
            let value: UInt32 = scalar.value
            return value < 32 && value != 9 && value != 10 && value != 13
        }.count

        // If less than 1% non-printable, treat as text
        if text.count > 0 && Double(nonPrintableCount) / Double(text.count) < 0.01 {
            return .text(text)
        }
    }

    // Binary data
    return .binary(data)
}

/// Generate a timestamped filename for binary output
public func generateTimestampFilename(extension ext: String, date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    let timestamp: String = formatter.string(from: date)
    return "/tmp/xplorer-\(timestamp).\(ext)"
}

/// Determine file extension from data (basic magic number detection)
public func detectFileExtension(from data: Data) -> String {
    guard data.count >= 8
    else {
        return "bin"
    }

    let bytes: [UInt8] = Array(data.prefix(8))

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
        return "png"
    }

    // JPEG: FF D8 FF
    if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
        return "jpg"
    }

    // GIF: 47 49 46 38
    if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 {
        return "gif"
    }

    // PDF: 25 50 44 46
    if bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46 {
        return "pdf"
    }

    // ZIP: 50 4B 03 04
    if bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04 {
        return "zip"
    }

    return "bin"
}

// MARK: - File Writing

/// Write data to a file at the specified path
public func writeDataToFile(_ data: Data, at path: String) throws {
    try data.write(to: URL(fileURLWithPath: path))
}
