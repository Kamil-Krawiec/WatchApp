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

    // MARK: - Sleep Analysis Fetch (Single Main Session)
    /// Fetch the last night’s main sleep session (e.g. ~10 pm → ~8 am) and return its duration in hours.
    func fetchSleepDuration(completion: @escaping (Double?) -> Void) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // Query the last 36 hours to be sure we span the previous evening → this morning
        let now = Date()
        let startWindow = Calendar.current.date(byAdding: .hour, value: -36, to: now)!
        let predicate = HKQuery.predicateForSamples(
            withStart: startWindow,
            end: now,
            options: [.strictStartDate, .strictEndDate]
        )

        let query = HKSampleQuery(
            sampleType: type,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        ) { _, results, error in
            if let error = error {
                print("❌ fetchSleepDuration error:", error)
                DispatchQueue.main.async { completion(nil) }
                return
            }
            guard let sleeps = results as? [HKCategorySample], !sleeps.isEmpty else {
                print("⚠️ fetchSleepDuration: no samples in window")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Keep only the actual "asleep" phases (value >= 1)
            let asleepSamples = sleeps.filter { $0.value >= HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }

            // Group into contiguous sessions (gap ≤ 30 min)
            let gapThreshold: TimeInterval = 30 * 60
            var sessions: [[HKCategorySample]] = []
            for sample in asleepSamples {
                if var lastSession = sessions.last,
                   let prev = lastSession.last,
                   sample.startDate.timeIntervalSince(prev.endDate) <= gapThreshold {
                    // extend current session
                    lastSession.append(sample)
                    sessions[sessions.count-1] = lastSession
                } else {
                    // start a new session
                    sessions.append([sample])
                }
            }

            // Find the session with the largest total duration
            func sessionDuration(_ session: [HKCategorySample]) -> TimeInterval {
                return session.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            }
            guard let mainSession = sessions.max(by: { sessionDuration($0) < sessionDuration($1) }) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Sum up that session's durations
            let totalSeconds = sessionDuration(mainSession)
            let hours = totalSeconds / 3600

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
