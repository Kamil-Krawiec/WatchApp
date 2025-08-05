//
//  HealthKitManager.swift
//  StressApp Watch App
//
//  Created by Kamil Krawiec on 05/06/2025.
//  Updated to fetch sleep and include it in stress computation
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
    // ADDED: last night’s sleep duration in hours
    @Published var latestSleepDuration: Double?   = nil

    @Published var authorizationRequested: Bool    = false
    @Published var authorizationSucceeded: Bool    = false

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    /// Request permission to read HRV, heart rate, and sleep from HealthKit.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        let toRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
//            new request
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        DispatchQueue.main.async { self.authorizationRequested = true }

        healthStore.requestAuthorization(toShare: [], read: toRead) { [weak self] success, _ in
            DispatchQueue.main.async {
                self?.authorizationSucceeded = success
                completion(success)
            }
        }
    }

    /// Fetch HRV, HR, and sleep; compute stress; store & sync.
    func fetchLatestData() {
        fetchLatestHRV { [weak self] hrv in
            guard let self = self else { return }
            self.fetchLatestHeartRate { hr in
                // ADDED: fetch sleep before creating sample
                self.fetchSleepDuration { sleep in
                    DispatchQueue.main.async {
                        self.latestHRV = hrv
                        self.latestHeartRate = hr
                        // ADDED: update latest sleep
                        self.latestSleepDuration = sleep

                        // Create a StressSample including sleep duration
                        let sample = StressSample(
                            date: Date(),
                            hrv: hrv,
                            heartRate: hr,
                            sleepDuration: sleep
                        )

                        self.latestStressLevel = sample.stressLevel
                        self.latestStressCategory = sample.stressCategory

                        // Persist locally
                        self.storage.appendSample(sample)

                        // Sync to iPhone via WCSession
                        self.send(sample: sample)
                    }
                }
            }
        }
    }

    /// Helper: fetch the single most‐recent HRV (SDNN).
    private func fetchLatestHRV(completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            let value = (samples?.first as? HKQuantitySample)?
                .quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
            DispatchQueue.main.async { completion(value) }
        }
        healthStore.execute(query)
    }

    /// Helper: fetch the single most‐recent heart rate.
    private func fetchLatestHeartRate(completion: @escaping (Double?) -> Void) {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(
            sampleType: type,
            predicate: nil,
            limit: 1,
            sortDescriptors: [sort]
        ) { _, samples, _ in
            let value = (samples?.first as? HKQuantitySample)?
                .quantity.doubleValue(for: HKUnit.count().unitDivided(by: HKUnit.minute()))
            DispatchQueue.main.async { completion(value) }
        }
        healthStore.execute(query)
    }

    // MARK: - Sleep Analysis Fetch (Fixed)
    /// Fetch sleep duration for the last night in hours,
    /// including all “asleep” phases (core, deep, REM, etc).
    func fetchSleepDuration(completion: @escaping (Double?) -> Void) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            print("⚠️ SleepAnalysis type unavailable")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date()).addingTimeInterval(-86400)
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: Date(),
            options: [.strictStartDate]
        )

        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: nil
        ) { _, results, error in
            if let error = error {
                print("❌ fetchSleepDuration error:", error)
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard let sleeps = results as? [HKCategorySample] else {
                print("⚠️ fetchSleepDuration: no samples returned")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Print out each sample with human‐readable phase
            for sample in sleeps {
                let phase: String
                switch sample.value {
                case HKCategoryValueSleepAnalysis.inBed.rawValue:
                    phase = "inBed"
                case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                    phase = "asleepUnspecified"
                case HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                    phase = "asleepCore"
                case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                    phase = "asleepDeep"
                case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                    phase = "asleepREM"
                default:
                    phase = "unknown(\(sample.value))"
                }
                print("  • \(sample.startDate) → \(sample.endDate) [\(phase)]")
            }

            // Include *all* asleep phases (value >= 1)
            let totalSeconds = sleeps
                .filter { $0.value >= HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }

            let hours = totalSeconds / 3600
            print("🕒 Calculated sleep hours:", hours)

            DispatchQueue.main.async { completion(hours) }
        }

        healthStore.execute(query)
    }

    /// Send a single StressSample to the paired iPhone via applicationContext
    private func send(sample: StressSample) {
        guard let session = session, session.activationState == .activated else { return }
        do {
            let data = try JSONEncoder().encode(sample)
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
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        // no-op
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String:Any]) {
        // no-op for watch
    }
}
