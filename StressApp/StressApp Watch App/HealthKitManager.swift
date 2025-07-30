//
//  HealthKitManager.swift
//  StressApp Watch App
//
//  Created by Kamil Krawiec on 05/06/2025.
//

import Foundation
import HealthKit
import Combine
import WatchConnectivity

final class HealthKitManager: NSObject, ObservableObject {
    private let healthStore = HKHealthStore()
    private let storage = StressStorage()
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    @Published var latestHeartRate: Double?       = nil   // bpm
    @Published var latestHRV: Double?             = nil   // ms
    @Published var latestStressLevel: Double?     = nil   // raw score
    @Published var latestStressCategory: StressCategory? = nil

    @Published var authorizationRequested: Bool    = false
    @Published var authorizationSucceeded: Bool    = false

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

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

        healthStore.requestAuthorization(toShare: [], read: toRead) { [weak self] success, _ in
            DispatchQueue.main.async {
                self?.authorizationSucceeded = success
                completion(success)
            }
        }
    }

    /// Fetch the most recent HRV and heart rate samples, compute stress, and store + sync.
    func fetchLatestData() {
        fetchLatestHRV { [weak self] hrv in
            guard let self = self else { return }
            self.fetchLatestHeartRate { hr in
                DispatchQueue.main.async {
                    self.latestHRV = hrv
                    self.latestHeartRate = hr

                    // Create a StressSample which computes both level and category
                    let sample = StressSample(date: Date(), hrv: hrv, heartRate: hr)
                    self.latestStressLevel = sample.stressLevel
                    self.latestStressCategory = sample.stressCategory

                    // Persist locally
                    self.storage.appendSample(sample)

                    // Sync to iPhone via WCSession applicationContext
                    self.send(sample: sample)
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

    /// Send a single StressSample to the paired iPhone via applicationContext
    private func send(sample: StressSample) {
        guard let session = session, session.activationState == .activated else { return }
        do {
            let data = try JSONEncoder().encode(sample)
            // We’ll wrap it in a dictionary under "newSample"
            try session.updateApplicationContext(["newSample": data])
        } catch {
            print("❌ WCSession send error: \(error)")
        }
    }

    /// Retrieve all stored StressSample objects (locally on watch).
    func getAllStoredSamples() -> [StressSample] {
        return storage.loadSamples()
    }
}

// MARK: - WCSessionDelegate (Watch side)

extension HealthKitManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith
                 activationState: WCSessionActivationState, error: Error?) {
        // no-op
    }

    /// iPhone might request context; send it all on demand.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String:Any]) {
        // no-op for watch
    }
}
