// Sources/BWMenuBar/EntryDetailView.swift
import SwiftUI

struct EntryDetailView: View {
    let entry: VaultEntry
    let service: RBWService
    @Binding var isPresented: Bool

    @State private var detail: EntryDetail?
    @State private var totpCode: String?
    @State private var totpSecondsRemaining: Int = 0
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var editingPassword = false
    @State private var editingNotes = false
    @State private var editPasswordText = ""
    @State private var editNotesText = ""
    @State private var editError: String?
    @State private var isSaving = false
    @State private var notesCopied = false
    @State private var totpTimer: Timer?
    @State private var isFetchingTOTP = false
    @State private var editBaselinePassword = ""
    @State private var editBaselineNotes: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isLoading {
                loadingView
            } else if let errorMessage {
                errorView(errorMessage)
            } else if let detail {
                ScrollView {
                    VStack(spacing: 10) {
                        credentialsCard(detail)
                        detailsCard(detail)
                        notesCard(detail)
                    }
                    .padding(12)
                }
            }
        }
        .frame(width: 360)
        .task { await loadDetail() }
        .onDisappear { totpTimer?.invalidate() }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button {
                isPresented = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Spacer()

            Text(entry.name)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)

            Spacer()

            Color.clear.frame(width: 50, height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Loading / Error

    private var loadingView: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Loading entry...")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await loadDetail() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Credentials Card

    @ViewBuilder
    private func credentialsCard(_ detail: EntryDetail) -> some View {
        let hasContent = !detail.username.isEmpty || !detail.password.isEmpty
            || detail.hasTotp || !detail.fields.isEmpty
        if hasContent {
            GroupCard {
                VStack(alignment: .leading, spacing: 8) {
                    if !detail.username.isEmpty {
                        fieldLabel("USERNAME")
                        CopyableField(text: detail.username) {
                            Text(detail.username)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                        }
                    }
                    if !detail.password.isEmpty {
                        HStack {
                            fieldLabel("PASSWORD")
                            Spacer()
                            if !editingPassword {
                                Button {
                                    editPasswordText = detail.password
                                    editBaselineNotes = detail.notes
                                    editError = nil
                                    editingPassword = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Edit password")
                            }
                        }
                        if editingPassword {
                            passwordEditField
                        } else {
                            PasswordCopyableField(password: detail.password)
                        }
                    }
                    if detail.hasTotp, let code = totpCode {
                        fieldLabel("TOTP")
                        totpField(code: code)
                    }
                    ForEach(Array(detail.fields.enumerated()), id: \.offset) { _, field in
                        fieldLabel(field.name.uppercased())
                        CopyableField(text: field.value) {
                            Text(field.value)
                                .font(.system(size: 13))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Details Card

    @ViewBuilder
    private func detailsCard(_ detail: EntryDetail) -> some View {
        let hasContent = !detail.uris.isEmpty || detail.folder != nil
        if hasContent {
            GroupCard {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(detail.uris.enumerated()), id: \.offset) { index, uri in
                        fieldLabel(detail.uris.count > 1 ? "URI \(index + 1)" : "URI")
                        CopyableField(text: uri) {
                            Text(uri)
                                .font(.system(size: 13))
                                .foregroundStyle(.blue)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    if let folder = detail.folder {
                        fieldLabel("FOLDER")
                        Text(folder)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 4)
                    }
                }
            }
        }
    }

    // MARK: - Notes Card

    @ViewBuilder
    private func notesCard(_ detail: EntryDetail) -> some View {
        if let notes = detail.notes, !notes.isEmpty {
            GroupCard(trailing: {
                HStack(spacing: 6) {
                    CopyAllButton(text: notes, isCopied: $notesCopied)
                    if !editingNotes {
                        Button {
                            editNotesText = notes
                            editBaselinePassword = detail.password
                            editError = nil
                            editingNotes = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Edit notes")
                    }
                }
            }) {
                if editingNotes {
                    notesEditField
                } else {
                    ZStack {
                        Text(notes)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(notesCopied ? 0.15 : 1)

                        if notesCopied {
                            Text("Copied")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: notesCopied)
                }
            }
        }
    }

    // MARK: - TOTP Field

    private func totpField(code: String) -> some View {
        HStack(spacing: 0) {
            CopyableField(text: code) {
                Text(code)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .tracking(4)
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)

            TOTPRing(secondsRemaining: totpSecondsRemaining)
                .padding(.leading, 10)
        }
    }

    // MARK: - Inline Edit Fields

    private var passwordEditField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("New password", text: $editPasswordText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13, design: .monospaced))
            if let editError {
                Text(editError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                Button("Save") {
                    Task { await savePasswordEdit() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(editPasswordText.isEmpty || isSaving)

                Button("Cancel") {
                    editingPassword = false
                    editError = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSaving)

                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var notesEditField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $editNotesText)
                .font(.system(size: 13))
                .frame(minHeight: 60, maxHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            if let editError {
                Text(editError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                Button("Save") {
                    Task { await saveNotesEdit() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isSaving)

                Button("Cancel") {
                    editingNotes = false
                    editError = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isSaving)

                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Helpers

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
    }

    // MARK: - Actions

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil

        guard let result = await service.getEntryDetail(for: entry) else {
            isLoading = false
            errorMessage = "Failed to load entry details."
            return
        }

        detail = result
        isLoading = false

        if result.hasTotp {
            await refreshTOTP()
            startTOTPTimer()
        }
    }

    private func refreshTOTP() async {
        totpCode = await service.getTOTPCode(for: entry)
        totpSecondsRemaining = 30 - (Int(Date().timeIntervalSince1970) % 30)
    }

    private func startTOTPTimer() {
        totpTimer?.invalidate()
        totpTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                let remaining = 30 - (Int(Date().timeIntervalSince1970) % 30)
                if totpSecondsRemaining <= 1 {
                    guard !isFetchingTOTP else { return }
                    isFetchingTOTP = true
                    await refreshTOTP()
                    isFetchingTOTP = false
                } else {
                    totpSecondsRemaining = remaining
                }
            }
        }
    }

    private func savePasswordEdit() async {
        isSaving = true
        editError = nil

        let success = await service.editEntry(
            for: entry,
            password: editPasswordText,
            notes: editBaselineNotes
        )

        isSaving = false

        if success {
            editingPassword = false
            await loadDetail()
        } else {
            editError = "Failed to save password."
        }
    }

    private func saveNotesEdit() async {
        isSaving = true
        editError = nil

        let success = await service.editEntry(
            for: entry,
            password: editBaselinePassword,
            notes: editNotesText.isEmpty ? nil : editNotesText
        )

        isSaving = false

        if success {
            editingNotes = false
            await loadDetail()
        } else {
            editError = "Failed to save notes."
        }
    }
}

// MARK: - GroupCard

private struct GroupCard<Trailing: View, Content: View>: View {
    let trailing: Trailing
    @ViewBuilder let content: Content

    init(
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if Trailing.self != EmptyView.self {
                HStack {
                    Spacer()
                    trailing
                }
            }
            content
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - PasswordCopyableField

private struct PasswordCopyableField: View {
    let password: String
    @State private var isHovering = false

    private var maskedText: String {
        String(repeating: "\u{2022}", count: min(password.count, 16))
    }

    var body: some View {
        CopyableField(text: password) {
            Group {
                if isHovering {
                    Text(password)
                        .font(.system(size: 13, design: .monospaced))
                } else {
                    Text(maskedText)
                        .font(.system(size: 13))
                }
            }
            .foregroundStyle(.primary)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - TOTPRing

private struct TOTPRing: View {
    let secondsRemaining: Int

    private var progress: Double {
        Double(secondsRemaining) / 30.0
    }

    private var ringColor: Color {
        secondsRemaining <= 5 ? .red : .green
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.2), lineWidth: 2.5)
                .frame(width: 28, height: 28)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: secondsRemaining)

            Text("\(secondsRemaining)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(ringColor)
        }
    }
}
