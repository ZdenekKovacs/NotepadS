import CryptoKit
import Foundation

/// Hash functions for the Text menu. A hash is computed over bytes:
/// - for the whole document, the bytes Save would write (so it matches `shasum file`);
/// - for a selection, its UTF-8 bytes as stored, line breaks included.
public enum TextHash: String, CaseIterable, Sendable {
    case sha256
    case sha1
    case md5

    /// The algorithm's name as people know it; not translated.
    public var name: String {
        switch self {
        case .sha256: return "SHA-256"
        case .sha1: return "SHA-1"
        case .md5: return "MD5"
        }
    }

    /// Lowercase hexadecimal digest, as `shasum` and `md5` print it.
    public func hexDigest(of data: Data) -> String {
        // SHA-1 and MD5 are "Insecure" in CryptoKit: fine for checksums, not for security.
        switch self {
        case .sha256: return Self.hex(SHA256.hash(data: data))
        case .sha1: return Self.hex(Insecure.SHA1.hash(data: data))
        case .md5: return Self.hex(Insecure.MD5.hash(data: data))
        }
    }

    private static func hex<Digest: Sequence>(_ digest: Digest) -> String where Digest.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
