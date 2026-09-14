import Foundation

enum AppInfo {
    static let repositoryURL = URL(string: "https://github.com/gonnabeafreeman/Layby")!

    @MainActor static var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let version, !version.isEmpty else { return L10n.text("未知版本") }
        guard let build, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}
