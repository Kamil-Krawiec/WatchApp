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
    // ADDED: sleep duration from HealthKit in hours
    let sleepDuration: Double?

    /// Stress score from 0 to 100, blending HR and HRV.
    var stressLevel: Double {
        return Self.computeStress(
            hrv: hrv,
            heartRate: heartRate,
            sleepDuration: sleepDuration
        )
    }

    /// Category: low (<50), moderate (50–75), high (>75)
    var stressCategory: StressCategory {
        return Self.category(for: stressLevel)
    }

    init(
        date: Date = Date(),
        hrv: Double?,
        heartRate: Double?,
        sleepDuration: Double? = nil
    ) {
        self.id = UUID()
        self.date = date
        self.hrv = hrv
        self.heartRate = heartRate
        self.sleepDuration = sleepDuration
    }


    // MARK: – Helper methods

    /// Compute a stress score (0–100) by averaging three components:
    /// • HR normalized to 0–1 (0…200 bpm),
    /// • inverted HRV normalized to 0–1 (0…200 ms),
    /// • inverted sleep normalized to 0–1 (0…10 hrs).
    private static func computeStress(
        hrv: Double?,
        heartRate: Double?,
        sleepDuration: Double?
    ) -> Double {
        // Normalize HR (clamp 0–200 bpm)
        let hrNorm: Double = {
            guard let hr = heartRate else { return 0.5 }
            return min(max(hr, 0), 200) / 200
        }()

        // Normalize HRV (clamp 0–200 ms, invert: higher HRV → lower stress)
        let hrvNorm: Double = {
            guard let h = hrv else { return 0.5 }
            let n = min(max(h, 0), 200) / 200
            return 1 - n
        }()

        // Normalize sleep (ideal 8 hrs, clamp 0–10 hrs, invert)
        let sleepNorm: Double = {
            guard let s = sleepDuration else { return 0.5 }
            let n = min(max(s, 0), 10) / 10
            return 1 - n
        }()

        // Weighted average: HR 30%, HRV 40%, Sleep 30%
        let weighted = hrNorm * 0.3 + hrvNorm * 0.4 + sleepNorm * 0.3
        return min(max(weighted * 100, 0), 100)
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
        case id
        case date
        case hrv
        case heartRate
        case sleepDuration
    }
}
