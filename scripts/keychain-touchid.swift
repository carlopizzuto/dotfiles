/// keychain-touchid — Store/retrieve Keychain items with Touch ID gate
/// Storage uses the regular Keychain (via `security` CLI).
/// Retrieval requires Touch ID via LAContext before returning the password.
///
/// Usage: keychain-touchid store <service> <account>   (reads password from stdin)
///        keychain-touchid get <service> <account>      (Touch ID prompt, then prints password)
///        keychain-touchid delete <service> <account>
import Foundation
import LocalAuthentication

func store(service: String, account: String) -> Bool {
    guard let line = readLine(strippingNewline: true), !line.isEmpty else {
        fputs("No input\n", stderr)
        return false
    }

    // Delete existing entry first
    let delArgs = ["/usr/bin/security", "delete-generic-password", "-s", service, "-a", account]
    let delProc = Process()
    delProc.executableURL = URL(fileURLWithPath: delArgs[0])
    delProc.arguments = Array(delArgs.dropFirst())
    delProc.standardOutput = FileHandle.nullDevice
    delProc.standardError = FileHandle.nullDevice
    try? delProc.run()
    delProc.waitUntilExit()

    // Add new entry
    let addArgs = ["/usr/bin/security", "add-generic-password", "-s", service, "-a", account, "-w", line]
    let addProc = Process()
    addProc.executableURL = URL(fileURLWithPath: addArgs[0])
    addProc.arguments = Array(addArgs.dropFirst())
    addProc.standardOutput = FileHandle.nullDevice
    addProc.standardError = FileHandle.nullDevice
    do {
        try addProc.run()
        addProc.waitUntilExit()
        return addProc.terminationStatus == 0
    } catch {
        fputs("Failed to run security: \(error)\n", stderr)
        return false
    }
}

func get(service: String, account: String) -> String? {
    // Touch ID check first
    let context = LAContext()
    var authError: NSError?

    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
        fputs("Biometrics unavailable: \(authError?.localizedDescription ?? "unknown")\n", stderr)
        return nil
    }

    let semaphore = DispatchSemaphore(value: 0)
    var authenticated = false

    context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: "unlock Bitwarden vault"
    ) { success, _ in
        authenticated = success
        semaphore.signal()
    }
    semaphore.wait()

    guard authenticated else {
        fputs("Touch ID denied\n", stderr)
        return nil
    }

    // Retrieve from Keychain via security CLI
    let proc = Process()
    let pipe = Pipe()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    proc.arguments = ["find-generic-password", "-s", service, "-a", account, "-w"]
    proc.standardOutput = pipe
    proc.standardError = FileHandle.nullDevice

    do {
        try proc.run()
    } catch {
        return nil
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    proc.waitUntilExit()

    guard proc.terminationStatus == 0 else { return nil }
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func delete(service: String, account: String) -> Bool {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    proc.arguments = ["delete-generic-password", "-s", service, "-a", account]
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    do {
        try proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus == 0
    } catch {
        return false
    }
}

// --- CLI ---

let args = CommandLine.arguments
guard args.count >= 4 else {
    fputs("Usage: keychain-touchid [store|get|delete] <service> <account>\n", stderr)
    exit(1)
}

let (cmd, service, account) = (args[1], args[2], args[3])

switch cmd {
case "store":
    exit(store(service: service, account: account) ? 0 : 1)
case "get":
    if let pw = get(service: service, account: account) {
        print(pw)
    } else {
        exit(1)
    }
case "delete":
    exit(delete(service: service, account: account) ? 0 : 1)
default:
    fputs("Unknown command: \(cmd)\n", stderr)
    exit(1)
}
