// StressStorage.swift
// Shared by both iOS and watchOS targets

import Foundation

/// File-based storage for StressSample arrays (JSON) in Documents.
final class StressStorage {
    private let fileName = "stress_samples.json"

    private var fileURL: URL? {
        do {
            let docs = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return docs.appendingPathComponent(fileName)
        } catch {
            print("❌ StressStorage: Could not locate Documents directory: \(error)")
            return nil
        }
    }

    /// Load all saved StressSample objects. Returns [] if none or on error.
    func loadSamples() -> [StressSample] {
        guard let url = fileURL else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let samples = try decoder.decode([StressSample].self, from: data)
            return samples.sorted { $0.date < $1.date }
        } catch {
            return []
        }
    }

    /// Save the given array of StressSample to disk (overwrites existing).
    func saveSamples(_ samples: [StressSample]) {
        guard let url = fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(samples)
            try data.write(to: url, options: [.atomicWrite])
        } catch {
            print("❌ StressStorage: Failed to save samples: \(error)")
        }
    }

    /// Append a single StressSample to storage (load → append → save).
    func appendSample(_ newSample: StressSample) {
        var existing = loadSamples()
        existing.append(newSample)
        saveSamples(existing)
    }
}
