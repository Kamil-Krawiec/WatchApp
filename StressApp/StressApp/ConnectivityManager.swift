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

//    Published is a wrapper that updates whenever variable is updated to all subscribers
    @Published private(set) var allSamples: [StressSample] = []

    override init() {
        super.init()
        session?.delegate = self
        session?.activate()
        // Load any locally stored samples
        allSamples = storage.loadSamples()
    }

    
    /// Public method to reload samples from storage
    func reloadSamples() {
        allSamples = storage.loadSamples()
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
        // no-op
    }
//    in swift there are externalName internalName: Type so _ means we dont need any exteral name so just easy triggering is sufficient
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        // We expect a key "newSample" whose value is Data
        if let newSampleData = applicationContext["newSample"] as? Data {
            do {
                let sample = try JSONDecoder().decode(StressSample.self, from: newSampleData)
                DispatchQueue.main.async {
                    // Append and save locally
                    self.storage.appendSample(sample)
                    // Reload allSamples so SwiftUI updates
                    self.allSamples = self.storage.loadSamples()
                }
            } catch {
                print("❌ Failed to decode incoming StressSample: \(error)")
            }
        }
    }

}
