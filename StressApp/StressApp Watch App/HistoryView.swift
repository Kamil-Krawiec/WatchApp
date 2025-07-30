//
//  HistoryView.swift
//  StressApp Watch App
//
//  Created by Kamil Krawiec on 05/06/2025.
import SwiftUI
import Charts  // watchOS 10+

struct HistoryView: View {
    @State private var allSamples: [StressSample] = []

    // Formatter for date and time in the list
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()

    var body: some View {
        VStack(spacing: 8) {
            Text("Stress History")
                .font(.headline)

            // Simple line chart of stress over time
            if #available(watchOS 10.0, *) {
                Chart {
                    ForEach(allSamples.sorted(by: { $0.date < $1.date })) { sample in
                        LineMark(
                            x: .value("Time", sample.date),
                            y: .value("Stress", sample.stressLevel)
                        )
                        .interpolationMethod(.monotone)
                        .foregroundStyle(.red.gradient)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(); AxisValueLabel(format: .dateTime.hour().minute()) }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 60)
                .padding(.horizontal, 4)
            }

            // Fallback list showing date/time and stress
            List {
                if allSamples.isEmpty {
                    Text("No stress data available.")
                        .foregroundColor(.gray)
                        .italic()
                } else {
                    ForEach(allSamples.sorted(by: { $0.date > $1.date })) { sample in
                        HStack {
                            Text(dateFormatter.string(from: sample.date))
                                .font(.caption2)
                            Spacer()
                            Text("\(Int(sample.stressLevel))")
                                .bold()
                                .foregroundColor(color(for: sample.stressLevel))
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .padding(8)
        .onAppear {
            allSamples = StressStorage().loadSamples()
        }
    }

    /// Color-code stress levels: low (<50)=green, moderate (50–75)=orange, high (>75)=red
    private func color(for level: Double) -> Color {
        switch level {
        case ..<50:    return .green
        case 50..<75:  return .orange
        default:       return .red
        }
    }
}

#Preview {
    NavigationStack {
        HistoryView()
    }
}
