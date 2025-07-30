//
//  IOSHistoryView.swift
//  StressApp
//
//  Created by Kamil Krawiec on 05/06/2025.
//


import SwiftUI
import Charts  // iOS 16+

struct IOSHistoryView: View {
    @StateObject private var connectivity = ConnectivityManager.shared
    @State private var selectedRange: TimeRange = .all

    // Time range options
enum TimeRange: String, CaseIterable, Identifiable {
        case last24h = "Last 24h"
        case last7d  = "Last 7d"
        case all     = "All"
        var id: Self { self }
    }

    // Filtered samples
    private var filteredSamples: [StressSample] {
        let cutoff: Date
        switch selectedRange {
        case .last24h:
            cutoff = Date().addingTimeInterval(-24*3600)
        case .last7d:
            cutoff = Date().addingTimeInterval(-7*24*3600)
        case .all:
            cutoff = .distantPast
        }
        return connectivity.allSamples.filter { $0.date >= cutoff }
    }

    // Fixed 0–100 scale
    private let stressRange: ClosedRange<Double> = 0...100

    // Date formatter for list
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    // Compute average
    private var averageStress: Double {
        let levels = filteredSamples.map { $0.stressLevel }
        guard !levels.isEmpty else { return 0 }
        return levels.reduce(0, +) / Double(levels.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stress History")
                .font(.largeTitle)
                .bold()

            // Range picker
            Picker("Range", selection: $selectedRange) {
                ForEach(TimeRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            // Chart
            if #available(iOS 16.0, *) {
                Chart(filteredSamples) { sample in
                    LineMark(
                        x: .value("Time", sample.date),
                        y: .value("Stress", sample.stressLevel)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.pink.gradient)
                }
                .chartYScale(domain: stressRange)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: selectedRange == .last24h ? 6 : 24)) {
                        AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 200)
                .padding(.horizontal)
            }

            // Summary
            HStack {
                Text("Average:")
                    .font(.headline)
                Spacer()
                Text("\(Int(averageStress))")
                    .font(.headline)
                    .foregroundColor(.pink)
            }
            .padding(.horizontal)

            // List
            List {
                ForEach(filteredSamples.sorted(by: { $0.date > $1.date })) { sample in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(dateFormatter.string(from: sample.date))
                                .font(.subheadline)
                            Text(sample.stressCategory.rawValue.capitalized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("\(Int(sample.stressLevel))")
                            .bold()
                            .foregroundColor(.pink)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
        }
        .padding(.top)
        .onAppear {
            connectivity.reloadSamples()
        }
    }
}

#Preview {
    IOSHistoryView()
}
