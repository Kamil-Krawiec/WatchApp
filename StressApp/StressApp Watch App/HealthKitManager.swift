//
//  HealthKitManager.swift
//  StressApp Watch App
//
//  Created by Kamil Krawiec on 05/06/2025.
//  Upgraded: reliable sync (queued + realtime), catch‑up handling, HK background delivery.
//

import Foundation
import HealthKit
import Combine
import WatchConnectivity

final class HealthKitManager: NSObject, ObservableObject {
    // MARK: - Stores & Sessions
    private let healthStore = HKHealthStore()
    private let storage = StressStorage()
    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil

    // MARK: - Published state
    @Published var latestHeartRate: Double?       = nil   // bpm
    @Published var latestHRV: Double?             = nil   // ms
    @Published var latestStressLevel: Double?     = nil   // raw score (0–100)
    @Published var latestStressCategory: StressCategory? = nil
    @Published var latestSleepDuration: Double?   = nil   // hours

    @Published var authorizationRequested: Bool    = false
    @Published var authorizationSucceeded: Bool    = false

    // MARK: - Debounce for frequent HK updates
    private var pendingFetch = false

    // MARK: - HK Anchors (optional incremental pulls)
    private let anchorKey = "HKAnchorKey.StressApp"
    private var anchor: HKQueryAnchor? {
        get {
            if let data = UserDefaults.standard.data(forKey: anchorKey) {
                return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
            }
            return nil
        }
        set {
            if let a = newValue,
               let data = try? NSKeyedArchiver.archivedData(withRootObject: a, requiringSecureCoding: true) {
                UserDefaults.standard.set(data, forKey: anchorKey)
            }
        }
    }

    // MARK: - Init
    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
    }

    // MARK: - Authorization
    /// Request permission to read HRV, heart rate, and sleep from HealthKit.
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }

        let toRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        DispatchQueue.main.async { self.authorizationRequested = true }

        healthStore.requestAuthorization(toShare: [], read: toRead) { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.authorizationSucceeded = success
                if success {
                    self.startBackgroundDelivery()
                    // Kick an initial fetch so UI isn’t empty
                    self.fetchLatestData()
                }
                completion(success)
            }
        }
    }

    // MARK: - Background delivery & observers
    private func startBackgroundDelivery() {
        let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let hr  = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let slp = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!

        let observe: (HKSampleType) -> Void = { [weak self] type in
            guard let self = self else { return }
            let q = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, _, error in
                if let error = error {
                    print("Observer error for \(type):", error)
                    return
                }
                // Coalesce bursts into a single fetch-send
                self?.scheduleFetch()
            }
            self.healthStore.execute(q)
            self.healthStore.enableBackgroundDelivery(for: type, frequency: .immediate) { ok, err in
                if !ok { print("⚠️ enableBackgroundDelivery failed for \(type):", err ?? "") }
            }
        }

        [hrv, hr, slp].forEach(observe)

        // Optional: run anchored pulls for HR/HRV to ensure no gaps
        anchoredPull(for: hrv)
        anchoredPull(for: hr)
        // Sleep is aggregated via custom window function below
    }

    private func scheduleFetch() {
        guard !pendingFetch else { return }
        pendingFetch = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.pendingFetch = false
            self?.fetchLatestData()
        }
    }

    // MARK: - Anchored incremental pull (simple)
    private func anchoredPull(for type: HKSampleType) {
        let q = HKAnchoredObjectQuery(type: type,
                                      predicate: nil,
                                      anchor: anchor,
                                      limit: HKObjectQueryNoLimit) { [weak self] _, _, _, newAnchor, error in
            guard let self = self else { return }
            if let error = error {
                print("Anchored query error:", error)
                return
            }
            self.anchor = newAnchor
            // After anchor advances, do a consolidated fetch
            self.scheduleFetch()
        }
        healthStore.execute(q)
    }

    // MARK: - Main data fetch + compute + persist + sync
    /// Fetch HRV, HR, and sleep; compute stress; store & sync to iPhone.
    func fetchLatestData() {
        fetchLatestHRV { [weak self] hrv in
            guard let self = self else { return }
            self.fetchLatestHeartRate { hr in
                self.fetchSleepDuration { sleep in
                    // Clamp sleep to a sane range before using
                    let clampedSleep: Double? = sleep.map { min(max($0, 0.0), 14.0) }

                    DispatchQueue.main.async {
                        self.latestHRV = hrv
                        self.latestHeartRate = hr
                        self.latestSleepDuration = clampedSleep

                        let sample = StressSample(
                            date: Date(),
                            hrv: hrv,
                            heartRate: hr,
                            sleepDuration: clampedSleep
                        )

                        self.latestStressLevel = sample.stressLevel
                        self.latestStressCategory = sample.stressCategory

                        // Persist locally
                        self.storage.appendSample(sample)

                        // Sync to iPhone (queued if not reachable)
                        self.send(sample: sample)
                    }
                }
            }
        }
    }

    // MARK: - HK Queries (latest values)
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

    // MARK: - Sleep Analysis (group to main session)
    /// Fetch the last night’s main sleep session (~evening → morning) and return its duration in hours.
    func fetchSleepDuration(completion: @escaping (Double?) -> Void) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

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

            // Keep only the "asleep" phases
            let asleepSamples = sleeps.filter { $0.value >= HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }

            // Group into contiguous sessions (gap ≤ 30 min)
            let gapThreshold: TimeInterval = 30 * 60
            var sessions: [[HKCategorySample]] = []
            for sample in asleepSamples {
                if var last = sessions.last,
                   let prev = last.last,
                   sample.startDate.timeIntervalSince(prev.endDate) <= gapThreshold {
                    last.append(sample)
                    sessions[sessions.count - 1] = last
                } else {
                    sessions.append([sample])
                }
            }

            func sessionDuration(_ session: [HKCategorySample]) -> TimeInterval {
                session.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            }

            guard let mainSession = sessions.max(by: { sessionDuration($0) < sessionDuration($1) }) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let hours = sessionDuration(mainSession) / 3600
            DispatchQueue.main.async { completion(hours) }
        }

        healthStore.execute(query)
    }

    // MARK: - WCSession sending
    /// Prefer queued, reliable delivery. Use realtime only if reachable.
    private func send(sample: StressSample) {
        guard let session = session, session.activationState == .activated else { return }
        do {
            let data = try JSONEncoder().encode(sample)
            if session.isReachable {
                session.sendMessage(["newSample": data], replyHandler: nil) { err in
                    print("⚠️ sendMessage failed, fallback to transferUserInfo: \(err)")
                    _ = session.transferUserInfo(["newSample": data])
                }
            } else {
                _ = session.transferUserInfo(["newSample": data])
            }
        } catch {
            print("❌ WCSession encoding error: \(error)")
        }
    }

    /// Batch send for catch‑ups or when you have many items.
    private func send(samples: [StressSample]) {
        guard let session = session, session.activationState == .activated, !samples.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(samples)
            if session.isReachable {
                session.sendMessage(["samples": data], replyHandler: nil) { err in
                    print("⚠️ batch sendMessage failed, fallback to transferUserInfo: \(err)")
                    _ = session.transferUserInfo(["samples": data])
                }
            } else {
                _ = session.transferUserInfo(["samples": data])
            }
        } catch {
            print("❌ WCSession encode batch error: \(error)")
        }
    }

    // MARK: - Public utility
    func getAllStoredSamples() -> [StressSample] {
        storage.loadSamples()
    }
}

// MARK: - WCSessionDelegate (Watch side)

extension HealthKitManager: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        // no-op
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        // Optionally do something when iPhone becomes reachable again
    }

    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String : Any]) {
        // no-op on watch
    }

    // iPhone asks: "send me anything since <unixSeconds>"
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let since = message["requestSamplesSince"] as? TimeInterval {
            let cutoff = Date(timeIntervalSince1970: since)
            let all = storage.loadSamples()
            let missing = all.filter { $0.date > cutoff }
            send(samples: missing)
        }
    }
}
