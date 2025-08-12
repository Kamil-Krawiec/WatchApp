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
    @State private var isSyncing: Bool = false

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

    private var minStress: Double {
        filteredSamples.map { $0.stressLevel }.min() ?? 0
    }

    private var maxStress: Double {
        filteredSamples.map { $0.stressLevel }.max() ?? 0
    }

    private var sampleCount: Int {
        filteredSamples.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Stress History")
                    .font(.largeTitle)
                    .bold()
                Spacer()
                Button {
                    isSyncing = true
                    connectivity.requestCatchUp()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        connectivity.reloadSamples()
                        isSyncing = false
                    }
                } label: {
                    Label("Sync", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isSyncing)
            }

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
                Chart {
                    // Area fill for a cleaner look
                    ForEach(filteredSamples) { sample in
                        AreaMark(
                            x: .value("Time", sample.date),
                            y: .value("Stress", sample.stressLevel)
                        )
                        .foregroundStyle(.pink.opacity(0.15))
                    }

                    // Main line
                    ForEach(filteredSamples) { sample in
                        LineMark(
                            x: .value("Time", sample.date),
                            y: .value("Stress", sample.stressLevel)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.pink)
                    }

                    // Threshold guides
                    RuleMark(y: .value("Moderate", 50))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.gray.opacity(0.5))
                    RuleMark(y: .value("High", 75))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.gray.opacity(0.5))

                    // Latest point marker with annotation
                    if let last = filteredSamples.last {
                        PointMark(
                            x: .value("Time", last.date),
                            y: .value("Stress", last.stressLevel)
                        )
                        .symbolSize(60)
                        .foregroundStyle(.pink)
                        .annotation(position: .topTrailing) {
                            Text("\(Int(last.stressLevel))")
                                .font(.caption2).bold()
                                .padding(6)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .chartYScale(domain: stressRange)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: selectedRange == .last24h ? 6 : (selectedRange == .last7d ? 8 : 10))) {
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 200)
                .padding(.horizontal)

            HStack(spacing: 12) {
                StatChip(title: "Avg", value: Int(averageStress).description)
                StatChip(title: "Min", value: Int(minStress).description)
                StatChip(title: "Max", value: Int(maxStress).description)
                StatChip(title: "Pts", value: sampleCount.description)
            }
            .padding(.horizontal)
            }

            // Summary (compact)
            Text("Average: \(Int(averageStress))")
                .font(.headline)
                .foregroundColor(.pink)
                .padding(.horizontal)

            // List
            List {
                ForEach(filteredSamples.sorted(by: { $0.date > $1.date })) { sample in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(dateFormatter.string(from: sample.date))
                                .font(.subheadline)
                            categoryPill(for: sample.stressCategory)
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

    private func categoryPill(for category: StressCategory) -> some View {
        let (label, color): (String, Color) = {
            switch category {
            case .low: return ("Low", .green)
            case .moderate: return ("Moderate", .orange)
            case .high: return ("High", .red)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundColor(color)
    }

    private struct StatChip: View {
        let title: String
        let value: String
        var body: some View {
            HStack(spacing: 6) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption).bold()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
        }
    }
}

#Preview {
    IOSHistoryView()
}
