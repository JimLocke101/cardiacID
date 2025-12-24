//
//  SharedUIComponents.swift
//  CardiacID
//
//  Shared UI components used across multiple views
//

import SwiftUI

// MARK: - Status Row

struct StatusRow: View {
    let label: String
    let value: String
    let isGood: Bool
    let colors: HeartIDColors

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(colors.text.opacity(0.7))

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: isGood ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(isGood ? .green : .red)
                    .font(.caption)

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(colors.text)
            }
        }
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    var disabled: Bool = false

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(disabled ? Color.gray.opacity(0.3) : color)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(disabled)
    }
}
