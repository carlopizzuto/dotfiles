// Sources/BWMenuBar/CopyableField.swift
import SwiftUI

/// A view that copies text to the clipboard on click, showing a brief "Copied" flash.
struct CopyableField<Content: View>: View {
    let text: String
    @ViewBuilder let content: Content
    @State private var showCopied = false

    var body: some View {
        Button {
            guard !showCopied else { return }
            Clipboard.copyAndClear(text)
            showCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCopied = false
            }
        } label: {
            ZStack {
                content
                    .opacity(showCopied ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: showCopied)

                Text("Copied")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .opacity(showCopied ? 1 : 0)
                    .offset(y: showCopied ? 0 : 4)
                    .animation(.easeInOut(duration: 0.2), value: showCopied)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A variant for the notes copy-all button that overlays "Copied" on an external content area.
/// The `isCopied` binding is controlled by the parent so the overlay can cover the notes text.
struct CopyAllButton: View {
    let text: String
    @Binding var isCopied: Bool

    var body: some View {
        Button {
            guard !isCopied else { return }
            Clipboard.copyAndClear(text)
            isCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                isCopied = false
            }
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Copy all")
    }
}
