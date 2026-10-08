import Foundation
import CryptoKit

/// Utility for computing content hashes used for clipboard deduplication.
enum CryptoHelper {
    /// Compute SHA-256 hash of raw data.
    static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Compute SHA-256 hash of a string (UTF-8 encoded).
    static func sha256(_ string: String) -> String {
        sha256(Data(string.utf8))
    }
}
