//  Services,SmartTrackIDService.swift
import Foundation
import CryptoKit

enum SmartTrackIDService {

    static func makeHash(for url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }

        let data = handle.readData(ofLength: 65536)
        try? handle.close()

        guard !data.isEmpty else { return nil }

        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
