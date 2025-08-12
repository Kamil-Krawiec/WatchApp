//
//  ContentView.swift
//  StressApp
//
//  Created by Kamil Krawiec on 04/06/2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var connectivity = ConnectivityManager.shared

    private var latestSample: StressSample? {
        connectivity.allSamples.last
    }

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

    /// Format hours as "xh ym" for display
    private func formatSleep(_ hours: Double?) -> String {
        guard let hours = hours else { return "--" }
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return "\(h)h \(m)m"
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("StressApp")
                    .font(.largeTitle)
                    .bold()

                if let sample = latestSample {
                    VStack(spacing: 8) {
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                            Text("\(Int(sample.hrv ?? 0)) ms")
                                .font(.title3)
                        }
                        HStack {
                            Image(systemName: "heart.fill")
                            Text("\(Int(sample.heartRate ?? 0)) bpm")
                                .font(.title3)
                        }
                        HStack {
                            Image(systemName: "bed.double.fill")
                            Text(formatSleep(sample.sleepDuration))
                                .font(.title3)
                        }
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundColor(stressColor(sample.stressCategory))
                            Text("\(Int(sample.stressLevel))")
                                .font(.title2)
                                .bold()
                                .foregroundColor(stressColor(sample.stressCategory))
                        }
                        Text(sample.stressCategory.rawValue.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(stressColor(sample.stressCategory).opacity(0.2), in: Capsule())
                    }
                } else {
                    Text("No data synced yet.")
                        .foregroundColor(.gray)
                }

                Button(action: {
                    // Ask the watch to send anything missing, then reload shortly after
                    connectivity.requestCatchUp()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        connectivity.reloadSamples()
                    }
                }) {
                    Label("Sync & Refresh", systemImage: "arrow.clockwise")
                }
                .padding()
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)

                NavigationLink(destination: IOSHistoryView()) {
                    Label("View History", systemImage: "chart.line.uptrend.xyaxis")
                }
                .padding()
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(8)

                Spacer()
            }
            .padding()
            .onAppear {
                // In case we want to push any missed samples to watch or vice versa
                // connectivity.sendAllToWatch()
            }
            .navigationTitle("StressApp")
        }
    }
}

#Preview {
    ContentView()
}
