import Foundation
import OSLog

enum AppEnvironment {
    static let subsystem = "com.local.mouseremap"
    static let supportedButtonRange = 2...31
    static let validatedThroughMajorVersion = 15
    static let validatedVersionsDescription = "macOS 13 Ventura, 14 Sonoma, and 15 Sequoia"

    static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    static func versionString(_ version: OperatingSystemVersion) -> String {
        "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
