// Copyright 2026 Soneso. Reference agent for the OZ smart-account demo.

import Foundation

/// Lowercase-hex encoding and validation for raw byte values.
///
/// The agent renders 32-byte Ed25519 seeds and public keys as 64-character
/// lowercase hex (matching the demo's "Delegate to agent" screen), and parses
/// operator-supplied hex seeds back into bytes.
public enum Hex {

    /// Encodes [bytes] as a lowercase hex string with no separators or prefix.
    public static func encode(_ bytes: [UInt8]) -> String {
        var output = String()
        output.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            output.append(hexDigits[Int(byte >> 4)])
            output.append(hexDigits[Int(byte & 0x0F)])
        }
        return output
    }

    /// Encodes [data] as a lowercase hex string.
    public static func encode(_ data: Data) -> String {
        encode([UInt8](data))
    }

    /// Returns whether [value] is a non-empty string of only hex digits with an
    /// even length.
    public static func isHexString(_ value: String) -> Bool {
        if value.isEmpty || value.count % 2 != 0 {
            return false
        }
        return value.allSatisfy { $0.isHexDigit }
    }

    /// Decodes [value] into raw bytes, or returns `nil` when [value] is not a
    /// valid even-length hex string.
    public static func decode(_ value: String) -> [UInt8]? {
        guard isHexString(value) else {
            return nil
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    private static let hexDigits: [Character] = Array("0123456789abcdef")
}
