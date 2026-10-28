import SwiftUI

struct SelectionActionBar: View {
    let selectedCount: Int
    let selectionSizeText: String
    let deletableCount: Int
    let isWorking: Bool
    let canStart: Bool
    let statusText: String?
    let deleteAction: () -> Void
    let cancelAction: () -> Void
    let startAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                selectionSummary
                Spacer()
                actionButtons
            }

            if let statusText {
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(selectedCount) selected")
                .font(.caption.weight(.semibold))
            Text(selectionSizeText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            if deletableCount > 0 && !isWorking {
                Button(role: .destructive, action: deleteAction) {
                    Label("Delete \(deletableCount)", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }

            if isWorking {
                Button(role: .cancel, action: cancelAction) {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            } else {
                Button(action: startAction) {
                    Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
            }
        }
        .font(.caption.weight(.semibold))
    }
}
