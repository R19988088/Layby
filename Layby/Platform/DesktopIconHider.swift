import AppKit

@MainActor
final class DesktopIconHider {
    private let domain = "com.apple.finder"

    var isHidden: Bool {
        let output = run("/usr/bin/defaults", arguments: ["read", domain, "CreateDesktop"])
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "false"
    }

    func start() {}
    func refresh() {}
    func stop() {}

    func toggle() {
        let value = isHidden ? "true" : "false"
        _ = run("/usr/bin/defaults", arguments: ["write", domain, "CreateDesktop", value])
        _ = run("/usr/bin/killall", arguments: ["Finder"])
    }

    private func run(_ path: String, arguments: [String]) -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try? process.run()
        process.waitUntilExit()
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
