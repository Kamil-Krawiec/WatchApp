//
//  StressSample.swift
//  StressApp
//
//  Created by Kamil Krawiec on 30/07/2025.
//
import Foundation

/// A labeled stress category, computed from a raw “stress score.”
enum StressCategory: String, Codable {
    case low
    case moderate
    case high
}

/// A single combined health sample: timestamp + HRV + heart rate.
/// “stressLevel” and “stressCategory” are derived via static logic.
struct StressSample: Identifiable, Codable {
    let id: UUID
    let date: Date
    let hrv: Double?         // HRV in milliseconds
    let heartRate: Double?   // Heart rate in beats per minute

    /// Stress score from 0 to 100, blending HR and HRV.
    var stressLevel: Double {
        return Self.computeStress(hrv: hrv, heartRate: heartRate)
    }

    /// Category: low (<50), moderate (50–75), high (>75)
    var stressCategory: StressCategory {
        return Self.category(for: stressLevel)
    }

    init(date: Date = Date(), hrv: Double?, heartRate: Double?) {
        self.id = UUID()
        self.date = date
        self.hrv = hrv
        self.heartRate = heartRate
    }

    // MARK: – Helper methods

    /// Compute a stress score (0–100) by averaging:
    ///  • HR normalized to 0–1 (0…200 bpm), and
    ///  • inverted HRV normalized to 0–1 (0…200 ms).
    private static func computeStress(hrv: Double?, heartRate: Double?) -> Double {
        guard let hrv = hrv, let hr = heartRate else { return 0 }

        // Normalize HR (clamp to 0–200 bpm)
        let hrNorm = min(max(hr, 0), 200) / 200
        // Normalize HRV (clamp to 0–200 ms and invert: higher HRV → lower stress)
        let hrvNorm = min(max(hrv, 0), 200) / 200
        let hrvComponent = 1 - hrvNorm

        // Average the two and scale to 0–100
        let score = ((hrNorm + hrvComponent) / 2) * 100

        // Clamp the final result
        return min(max(score, 0), 100)
    }

    /// Bucket a raw score into a labeled category.
    private static func category(for score: Double) -> StressCategory {
        switch score {
        case ..<50:
            return .low
        case 50..<75:
            return .moderate
        default:
            return .high
        }
    }

    // MARK: – Codable overrides: encode only raw inputs
    enum CodingKeys: String, CodingKey {
        case id, date, hrv, heartRate
    }
}
