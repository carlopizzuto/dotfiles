// Sources/BWMenuBar/AddEntryView.swift
import SwiftUI

struct AddEntryView: View {
    let service: RBWService
    @Binding var isPresented: Bool
    var onSaved: () -> Void

    @State private var name = ""
    @State private var user = ""
    @State private var password = ""
    @State private var uri = ""
    @State private var folder = ""

    @State private var generateMode = false
    @State private var passwordIsGenerated = false
    @State private var genLength: Double = 16
    @State private var noSymbols = false
    @State private var onlyNumbers = false
    @State private var diceware = false
    @State private var suppressRegenerate = false
    @State private var isRegenerating = false

    @State private var isSaving = false
    @State private var errorMessage: String?

    private var lengthRange: ClosedRange<Double> {
        diceware ? 3...10 : 8...64
    }

    private var lengthDefault: Double {
        diceware ? 5 : 16
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    formFields
                    passwordSection
                    generateToggle
                    if generateMode {
                        generateOptions
                    }
                    optionalFields
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                    saveButton
                }
                .padding(12)
            }
        }
        .frame(width: 360)
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

            Text("New Login")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            // Balance the back button width
            Color.clear.frame(width: 50, height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Form fields

    private var formFields: some View {
        VStack(spacing: 10) {
            LabeledField("NAME *") {
                TextField("Entry name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledField("USERNAME") {
                TextField("email or username", text: $user)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Password section

    private var passwordSection: some View {
        LabeledField("PASSWORD") {
            HStack(spacing: 6) {
                if generateMode {
                    TextField("password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 13, design: .monospaced))
                } else {
                    SecureField("password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                if !password.isEmpty {
                    Button {
                        Clipboard.copyAndClear(password)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy password")
                }
            }
        }
        .onChange(of: password) { _, _ in
            // User edited the password — no longer matches generated value
            if !isRegenerating { passwordIsGenerated = false }
        }
    }

    // MARK: - Generate toggle

    private var generateToggle: some View {
        HStack {
            Toggle("Generate Password", isOn: $generateMode)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
            if generateMode {
                Button {
                    Task { await regenerate() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                        Text("Regenerate")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .disabled(isRegenerating || isSaving)
            }
        }
        .onChange(of: generateMode) { _, newValue in
            if newValue {
                Task { await regenerate() }
            }
        }
    }

    // MARK: - Generate options

    private var generateOptions: some View {
        VStack(spacing: 8) {
            // Length slider
            HStack {
                Text(diceware ? "WORDS" : "LENGTH")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Slider(value: $genLength, in: lengthRange, step: 1)
                    .frame(width: 140)
                Text("\(Int(genLength))")
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 24, alignment: .trailing)
            }

            // Option pills
            HStack(spacing: 6) {
                OptionPill("No symbols", isOn: $noSymbols)
                    .disabled(diceware)
                OptionPill("Numbers only", isOn: $onlyNumbers)
                    .disabled(diceware)
                OptionPill("Diceware", isOn: $diceware)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onChange(of: genLength) { _, _ in
            guard !suppressRegenerate else { return }
            Task { await regenerate() }
        }
        .onChange(of: noSymbols) { _, _ in
            guard !suppressRegenerate else { return }
            Task { await regenerate() }
        }
        .onChange(of: onlyNumbers) { _, _ in
            guard !suppressRegenerate else { return }
            Task { await regenerate() }
        }
        .onChange(of: diceware) { _, newValue in
            suppressRegenerate = true
            if newValue {
                noSymbols = false
                onlyNumbers = false
                genLength = 5
            } else {
                genLength = 16
            }
            suppressRegenerate = false
            Task { await regenerate() }
        }
    }

    // MARK: - Optional fields

    private var optionalFields: some View {
        VStack(spacing: 10) {
            LabeledField("URI") {
                TextField("https://example.com", text: $uri)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledField("FOLDER") {
                TextField("optional", text: $folder)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: - Save button

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            } else {
                Text("Save Entry")
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
    }

    // MARK: - Actions

    private func regenerate() async {
        guard !isRegenerating else { return }
        isRegenerating = true
        defer { isRegenerating = false }
        guard let pw = await service.generatePassword(
            length: Int(genLength),
            noSymbols: noSymbols,
            onlyNumbers: onlyNumbers,
            diceware: diceware
        ) else { return }
        password = pw
        passwordIsGenerated = true
    }

    private func save() async {
        isSaving = true
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let success: Bool

        if generateMode && passwordIsGenerated {
            // User didn't edit the generated password — use rbw generate to save
            success = await service.generateEntry(
                name: trimmedName, user: user, length: Int(genLength),
                uri: uri, folder: folder,
                noSymbols: noSymbols, onlyNumbers: onlyNumbers, diceware: diceware
            )
        } else {
            // Manual password or user edited the generated one — use rbw add
            success = await service.addEntry(
                name: trimmedName, user: user, password: password,
                uri: uri, folder: folder
            )
        }

        isSaving = false

        if success {
            isPresented = false
            onSaved()
        } else {
            errorMessage = "Failed to save entry. Check if an entry with this name already exists."
        }
    }
}

// MARK: - Reusable components

private struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private struct OptionPill: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            Text(title)
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isOn ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                .foregroundStyle(isOn ? .primary : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}
