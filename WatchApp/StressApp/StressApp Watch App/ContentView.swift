//
//  ContentView.swift
//  StressApp Watch App
//
//  Created by Kamil Krawiec on 04/06/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager()
    @State private var statusMessage: String = "Requesting authorization…"
    @State private var isLoading: Bool = false

    /// Determine color for stress category
    private func stressColor(_ category: StressCategory?) -> Color {
        switch category {
        case .low:
            return .green
        case .moderate:
            return .orange
        case .high:
            return .red
        default:
            return .gray
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Stress Predictor")
                        .font(.headline)

                    // Show latest HRV & heart rate if available
                    if let hrv = healthKitManager.latestHRV {
                        Text("HRV: \(Int(hrv)) ms")
                            .font(.title3)
                    } else {
                        Text("HRV: —")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }

                    if let hr = healthKitManager.latestHeartRate {
                        Text("HR: \(Int(hr)) bpm")
                            .font(.title3)
                    } else {
                        Text("HR: —")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }

                    // Show computed stress level and category
                    if let level = healthKitManager.latestStressLevel {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(stressColor(healthKitManager.latestStressCategory))
                                .frame(width: 10, height: 10)
                            Text("Stress: \(Int(level))")
                                .font(.title2)
                                .bold()
                                .foregroundColor(stressColor(healthKitManager.latestStressCategory))
                        }
                    } else {
                        Text("Stress: —")
                            .font(.title2)
                            .foregroundColor(.gray)
                    }

                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button(action: {
                        isLoading = true
                        healthKitManager.fetchLatestData()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isLoading = false
                        }
                    }) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .padding(.top, 8)

                    NavigationLink(destination: HistoryView()) {
                        Label("View History", systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .padding(.top, 8)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Stress Predictor")
            .onAppear {
                healthKitManager.requestAuthorization { success in
                    if success {
                        statusMessage = "Authorized ✅\nFetching data…"
                        healthKitManager.fetchLatestData()
                    } else {
                        statusMessage = "HealthKit authorization denied."
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
