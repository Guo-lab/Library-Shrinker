import SwiftUI

struct ImageAssetRow: View {
    let item: ImageAssetItem
    let isSelected: Bool
    let targetByteSize: Int64
    let compressionRecord: CompressionRecord?
    let compressionRole: ImageCompressionRole
    let isCompressedChild: Bool
    let selectionAction: () -> Void
    let previewAction: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if isCompressedChild {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
            }

            if compressionRole == .compressedCopy {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.blue)
                    .frame(width: 20, height: 24)
            } else {
                Button(action: selectionAction) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.callout)
                        .foregroundStyle(isSelected ? .blue : .secondary)
                        .frame(width: 20, height: 24)
                }
                .buttonStyle(.plain)
            }

            Button(action: previewAction) {
                ImageThumbnailView(asset: item.asset)
                    .frame(width: 58, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(item.displayName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    if compressionRole != .original {
                        Text(compressionRole == .compressedCopy ? "Compressed" : "Original")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(compressionRole == .compressedCopy ? .blue : .green)
                    }
                }
                Text(item.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(secondaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if compressionRole != .compressedCopy {
                    selectionAction()
                }
            }

            Text(item.fileSizeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 58, alignment: .trailing)
        }
        .listRowInsets(EdgeInsets(
            top: 8,
            leading: isCompressedChild ? 20 : 12,
            bottom: 8,
            trailing: 12
        ))
    }

    private var secondaryText: String {
        if compressionRole == .originalWithCompressedCopy,
           let compressionRecord {
            let compressed = ByteCountFormatter.libraryShrinkerFormatter.string(
                fromByteCount: compressionRecord.compressedByteSize
            )
            return "\(item.fileSizeText) → \(compressed) • safe original retained"
        }
        if compressionRole == .compressedCopy,
           let compressionRecord {
            let saved = ByteCountFormatter.libraryShrinkerFormatter.string(
                fromByteCount: compressionRecord.savedByteSize
            )
            return "JPEG • saved \(saved)"
        }
        let targetText = ByteCountFormatter.libraryShrinkerFormatter.string(
            fromByteCount: targetByteSize
        )
        return "Target about \(targetText)"
    }
}
