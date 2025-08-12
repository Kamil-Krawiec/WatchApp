//
//  ConnectivityManager.swift
//  StressApp
//
//  Created by Kamil Krawiec on 30/07/2025.
//

import Foundation
import WatchConnectivity
import Combine

final class ConnectivityManager: NSObject, ObservableObject {
    static let shared = ConnectivityManager()

    private let session: WCSession? = WCSession.isSupported() ? WCSession.default : nil
    private let storage = StressStorage()

    private let lastSyncDateKey = "ConnectivityManager.lastSyncDate"
    private var isReachable: Bool { session?.isReachable == true }

//    Published is a wrapper that updates whenever variable is updated to all subscribers
    @Published private(set) var allSamples: [StressSample] = []

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
        // Load any locally stored samples
        allSamples = storage.loadSamples()
        // Catch-up is triggered on activation callback and reachability changes
    }

    
    /// Public method to reload samples from storage
    func reloadSamples() {
        allSamples = storage.loadSamples()
    }

    // MARK: - Sync helpers

    /// Persist and read last successful sync cutoff on iOS side
    private func loadLastSyncDate() -> Date {
        (UserDefaults.standard.object(forKey: lastSyncDateKey) as? Date) ?? Date(timeIntervalSince1970: 0)
    }

    private func saveLastSyncDate(_ date: Date) {
        UserDefaults.standard.set(date, forKey: lastSyncDateKey)
    }

    /// Merge incoming samples, avoid duplicates by `id`, update storage and published array.
    private func ingestSamples(_ samples: [StressSample]) {
        guard !samples.isEmpty else { return }

        // Load existing, build a set of existing IDs to dedupe.
        let existing = storage.loadSamples()
        let existingIDs = Set(existing.map { $0.id })

        let newOnes = samples.filter { !existingIDs.contains($0.id) }
        guard !newOnes.isEmpty else { return }

        // Append and persist one by one using current storage API
        for s in newOnes.sorted(by: { $0.date < $1.date }) {
            storage.appendSample(s)
        }

        // Update published and last sync timestamp on main thread
        let newestDate = (newOnes.map { $0.date }.max()) ?? Date()
        DispatchQueue.main.async {
            self.allSamples = self.storage.loadSamples()
            self.saveLastSyncDate(newestDate)
        }
    }

    /// Ask the watch for any samples we might be missing since the last sync cutoff.
    func requestCatchUp() {
        let since = loadLastSyncDate().timeIntervalSince1970
        let payload: [String: Any] = ["requestSamplesSince": since]

        if isReachable {
            session?.sendMessage(payload, replyHandler: nil, errorHandler: { err in
                print("⚠️ sendMessage requestSamplesSince failed: \(err)")
            })
        } else {
            _ = session?.transferUserInfo(payload)
        }
    }
}

// MARK: - WCSessionDelegate (iOS side)

extension ConnectivityManager: WCSessionDelegate {
    func sessionDidBecomeInactive(_ session: WCSession) {
        //
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        //
    }
    
    func session(_ session: WCSession, activationDidCompleteWith
                 activationState: WCSessionActivationState, error: Error?) {
        // When activation completes on iOS, immediately request any missing samples
        if error == nil && activationState == .activated {
            requestCatchUp()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if session.isReachable {
            // Phone can talk to the watch in real time now — try to catch up
            requestCatchUp()
        }
    }

    //    in swift there are externalName internalName: Type so _ means we dont need any exteral name so just easy triggering is sufficient
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        // Support either a single sample (Data) or a batch (Data encoding [StressSample])
        if let batchData = applicationContext["samples"] as? Data {
            do {
                let samples = try JSONDecoder().decode([StressSample].self, from: batchData)
                ingestSamples(samples)
            } catch {
                print("❌ Failed to decode incoming [StressSample] from applicationContext: \(error)")
            }
            return
        }

        if let newSampleData = applicationContext["newSample"] as? Data {
            do {
                let sample = try JSONDecoder().decode(StressSample.self, from: newSampleData)
                ingestSamples([sample])
            } catch {
                print("❌ Failed to decode incoming StressSample: \(error)")
            }
        }
    }

    // Queued, background-friendly path — recommended for reliable delivery
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        if let batchData = userInfo["samples"] as? Data {
            do {
                let samples = try JSONDecoder().decode([StressSample].self, from: batchData)
                ingestSamples(samples)
            } catch {
                print("❌ Failed to decode [StressSample] from userInfo: \(error)")
            }
            return
        }

        if let newSampleData = userInfo["newSample"] as? Data {
            do {
                let sample = try JSONDecoder().decode(StressSample.self, from: newSampleData)
                ingestSamples([sample])
            } catch {
                print("❌ Failed to decode StressSample from userInfo: \(error)")
            }
        }
    }

    // Real-time message (when reachable). Expect optional reply with samples.
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if let batchData = message["samples"] as? Data {
            do {
                let samples = try JSONDecoder().decode([StressSample].self, from: batchData)
                ingestSamples(samples)
            } catch {
                print("❌ Failed to decode [StressSample] from message: \(error)")
            }
        }
    }
}
