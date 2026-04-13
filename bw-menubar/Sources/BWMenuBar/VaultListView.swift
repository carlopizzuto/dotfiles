// Sources/BWMenuBar/VaultListView.swift
import SwiftUI

struct VaultListView: View {
    let service: RBWService
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingAddEntry = false
    @State private var confirmationMessage: String?
    @State private var selectedEntry: VaultEntry?

    private var filtered: [VaultEntry] {
        service.entries.filter { $0.matches(query: searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let selectedEntry {
                EntryDetailView(
                    entry: selectedEntry,
                    service: service,
                    isPresented: Binding(
                        get: { self.selectedEntry != nil },
                        set: { if !$0 { self.selectedEntry = nil } }
                    )
                )
            } else if showingAddEntry {
                AddEntryView(service: service, isPresented: $showingAddEntry) {
                    Task {
                        await service.loadEntries()
                        confirmationMessage = "Entry added"
                        try? await Task.sleep(for: .seconds(2))
                        if !Task.isCancelled { confirmationMessage = nil }
                    }
                }
            } else {
                switch service.state {
                case .loading:
                    loadingView
                case .locked:
                    lockedView
                case .error(let message):
                    errorView(message)
                case .ready:
                    readyView
                }
            }
        }
        .frame(width: 360)
        .task {
            await service.startup()
        }
    }

    // MARK: - State views

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Loading vault...")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
        }
        .frame(height: 120)
    }

    private var lockedView: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Vault is locked")
                .font(.headline)
            Button("Unlock Vault") {
                Task {
                    let success = await service.unlock()
                    if success {
                        await service.startup()
                    }
                }
            }
            .controlSize(.large)
        }
        .frame(height: 160)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28))
                .foregroundStyle(.yellow)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await service.startup() }
            }
        }
        .padding()
        .frame(height: 160)
    }

    // MARK: - Ready state (search + list)

    private var readyView: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search vault...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.5))

            Divider()

            if filtered.isEmpty {
                Text("No matching entries")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                    .frame(height: 80)
            } else {
                List(filtered) { entry in
                    EntryRow(entry: entry, onSelect: {
                        selectedEntry = entry
                    }, onQuickCopy: {
                        Task { await copyPassword(for: entry) }
                    })
                    .contextMenu {
                        Button("Copy Password") {
                            Task { await copyPassword(for: entry) }
                        }
                        Button("Copy Username") {
                            guard !entry.user.isEmpty else { return }
                            Clipboard.copyAndClear(entry.user)
                        }
                    }
                }
                .listStyle(.plain)
                .frame(maxHeight: 420)
            }

            // Entry count footer
            HStack {
                if let confirmationMessage {
                    Text(confirmationMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.green)
                } else {
                    Text("\(filtered.count) entries")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    showingAddEntry = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Add entry")
                Button {
                    Task {
                        await service.sync()
                        await service.loadEntries()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Sync vault")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Actions

    private func copyPassword(for entry: VaultEntry) async {
        guard let password = await service.getPassword(for: entry) else { return }
        Clipboard.copyAndClear(password)
    }

    private func closePopover() {
        dismiss()
        // Fallback: dismiss() may not be wired for MenuBarExtra(.window)
        NSApp.keyWindow?.close()
    }
}

// MARK: - Entry Row

private struct EntryRow: View {
    let entry: VaultEntry
    let onSelect: () -> Void
    let onQuickCopy: () -> Void
    @State private var showCopied = false

    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    ZStack(alignment: .leading) {
                        Text(entry.name)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .opacity(showCopied ? 0 : 1)
                            .animation(.easeInOut(duration: 0.2), value: showCopied)

                        Text("Copied")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                            .opacity(showCopied ? 1 : 0)
                            .offset(y: showCopied ? 0 : 4)
                            .animation(.easeInOut(duration: 0.2), value: showCopied)
                    }
                    if !entry.user.isEmpty {
                        Text(entry.user)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    guard !showCopied else { return }
                    onQuickCopy()
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy password")
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}
