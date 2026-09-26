//
//  VideoAssetRow.swift
//  Library Shrinker
//

import Photos
import SwiftUI

struct VideoAssetRow: View {
    let video: VideoAssetItem
    let isSelected: Bool
    let compressionRecord: CompressionRecord?
    let compressionRole: VideoCompressionRole
    let targetByteSize: Int64
    let showsIndividualRatio: Bool
    let isCompressedChild: Bool
    let selectionAction: () -> Void
    let previewAction: () -> Void

    var body: some View {
        HStack(spacing: 6) {
                if isCompressedChild {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                }

                Button(action: selectionAction) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.callout)
                        .foregroundStyle(isSelected ? .blue : .secondary)
                        .frame(width: 20, height: 24)
                }
                .buttonStyle(.plain)

                Button(action: previewAction) {
                    VideoThumbnailView(asset: video.asset)
                        .frame(width: 54, height: 42)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            Image(systemName: "play.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(video.displayName)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if compressionRole != .original {
                            Label(roleTitle, systemImage: roleIcon)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(roleColor)
                                .lineLimit(1)
                        }
                    }

                    Text(video.detailText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(secondaryDetailText)
                        .font(.caption)
                        .foregroundStyle(secondaryDetailColor)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: selectionAction)

                Text(video.fileSizeMegabytesText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: selectionAction)
        }
        .listRowInsets(EdgeInsets(
            top: 8,
            leading: isCompressedChild ? 20 : 12,
            bottom: 8,
            trailing: 12
        ))
    }

    private var secondaryDetailText: String {
        if compressionRole == .originalWithCompressedCopy {
            return "Compressed copy verified • safe to delete original"
        }

        if let compressionRecord, compressionRole == .compressedCopy {
            let compressedSize = ByteCountFormatter.libraryShrinkerFormatter.string(
                fromByteCount: compressionRecord.compressedByteSize
            )
            return "Compressed: \(compressedSize) • \(compressionRecord.presetName)"
        }

        return video.estimatedCompressionText(
            targetByteSize: targetByteSize,
            showsIndividualRatio: showsIndividualRatio
        )
    }

    private var secondaryDetailColor: Color {
        compressionRole == .original ? .secondary : roleColor
    }

    private var roleTitle: String {
        compressionRole == .compressedCopy ? "Compressed" : "Original"
    }

    private var roleIcon: String {
        compressionRole == .compressedCopy ? "arrow.down.circle.fill" : "checkmark.seal.fill"
    }

    private var roleColor: Color {
        compressionRole == .compressedCopy ? .blue : .green
    }
}
