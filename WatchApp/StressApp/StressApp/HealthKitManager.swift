//
//  HealthKitManager.swift
//  StressApp
//
//  Created by Kamil Krawiec on 30/07/2025.
//

import Foundation
import HealthKit
import Combine

/// ObservableObject for iOS: requests HealthKit authorization,
/// fetches the most recent HRV and heart rate, computes stress, and persists each reading.
final class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()
    private let storage = StressStorage()

    @Published var latestHeartRate: Double?       = nil   // bpm
    @Published var latestHRV: Double?             = nil   // ms
    @Published var latestStressLevel: Double?     = nil   // raw score
    @Published var latestStressCategory: StressCategory? = nil

    @Published var authorizationRequested: Bool    = false
    @Published var authorizationSucceeded: Bool    = false
    @Published var authorizationError: String?     = nil

    /// Request permission to read HRV and heart rate from HealthKit.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }

        guard
            let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
            let hrType  = HKQuantityType.quantityType(forIdentifier: .heartRate)
        else {
            completion(false)
            return
        }

        let toRead: Set<HKObjectType> = [hrvType, hrType]
        DispatchQueue.main.async { self.authorizationRequested = true }

        healthStore.requestAuthorization(toShare: [], read: toRead) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.authorizationSucceeded = success
                if let err = error {
                    self?.authorizationError = err.localizedDescription
                }
                completion(success)
            }
        }
    }

    /// Fetch the most recent HRV and heart rate samples, compute stress, and store.
    func fetchLatestData() {
        fetchLatestHRV { [weak self] hrv in
            guard let self = self else { return }
            self.fetchLatestHeartRate { hr in
                DispatchQueue.main.async {
                    self.latestHRV = hrv
                    self.latestHeartRate = hr

                    let sample = StressSample(
                        date: Date(),
                        hrv: hrv,
                        heartRate: hr
                    )
                    self.latestStressLevel = sample.stressLevel
                    self.latestStressCategory = sample.stressCategory

                    self.storage.appendSample(sample)
                }
            }
        }
    }

    /// Helper: fetch the single most‐recent HRV (SDNN). Completion on main thread.
    private func fetchLatestHRV(completion: @escaping (Double?) -> Void) {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: hrvType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            if let sample = samples?.first as? HKQuantitySample {
                let hrvMs = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                DispatchQueue.main.async { completion(hrvMs) }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
        healthStore.execute(query)
    }

    /// Helper: fetch the single most‐recent heart rate sample. Completion on main thread.
    private func fetchLatestHeartRate(completion: @escaping (Double?) -> Void) {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: hrType,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            if let sample = samples?.first as? HKQuantitySample {
                let hrBpm = sample.quantity.doubleValue(
                    for: HKUnit.count().unitDivided(by: HKUnit.minute())
                )
                DispatchQueue.main.async { completion(hrBpm) }
            } else {
                DispatchQueue.main.async { completion(nil) }
            }
        }
        healthStore.execute(query)
    }

    /// Retrieve all stored StressSample objects.
    func getAllStoredSamples() -> [StressSample] {
        return storage.loadSamples()
    }
}
