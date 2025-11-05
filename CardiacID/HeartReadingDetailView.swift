import SwiftUI

struct HeartReadingDetailView: View {
    let reading: HeartReading
    private let colors = HeartIDColors()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Heart Rate Display
                VStack(spacing: 8) {
                    Text("\(reading.heartRate) BPM")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundColor(colors.accent)
                    
                    Text("Heart Rate")
                        .font(.subheadline)
                        .foregroundColor(colors.text.opacity(0.7))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
                
                // Time Info
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recorded on:")
                        .font(.headline)
                    
                    if let timestamp = reading.timestamp {
                        Text(timestamp, formatter: itemFormatter)
                            .font(.subheadline)
                            .foregroundColor(colors.text.opacity(0.8))
                    }
                }
                .padding()
                .background(colors.surface)
                .cornerRadius(16)
                
                // Notes
                if let notes = reading.notes, !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Notes:")
                            .font(.headline)
                        
                        Text(notes)
                            .font(.subheadline)
                            .foregroundColor(colors.text.opacity(0.8))
                    }
                    .padding()
                    .background(colors.surface)
                    .cornerRadius(16)
                }
            }
            .padding()
        }
        .background(colors.background)
        .navigationTitle("Heart Reading Details")
    }
}

// MARK: - Formatter
private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .long
    formatter.timeStyle = .medium
    return formatter
}()

#Preview {
    HeartReadingDetailView(reading: HeartReading())
        .preferredColorScheme(.dark)
}
