import Carbon.HIToolbox
import CoreGraphics
import Foundation

extension CGEventFlags: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

struct KeyboardShortcut: Hashable {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
}

enum ButtonAction: Hashable, Codable {
    case prevSpace
    case nextSpace
    case missionControl
    case appExpose
    case launchpad
    case showDesktop
    case custom(keyCode: CGKeyCode, modifiers: CGEventFlags)
    case none

    private enum CodingKeys: String, CodingKey {
        case kind
        case keyCode
        case modifiers
    }

    private enum Kind: String, Codable {
        case prevSpace
        case nextSpace
        case missionControl
        case appExpose
        case launchpad
        case showDesktop
        case custom
        case none
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .prevSpace:
            self = .prevSpace
        case .nextSpace:
            self = .nextSpace
        case .missionControl:
            self = .missionControl
        case .appExpose:
            self = .appExpose
        case .launchpad:
            self = .launchpad
        case .showDesktop:
            self = .showDesktop
        case .none:
            self = .none
        case .custom:
            let keyCode = try container.decode(CGKeyCode.self, forKey: .keyCode)
            let modifiersRawValue = try container.decode(CGEventFlags.RawValue.self, forKey: .modifiers)
            self = .custom(keyCode: keyCode, modifiers: CGEventFlags(rawValue: modifiersRawValue))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .prevSpace:
            try container.encode(Kind.prevSpace, forKey: .kind)
        case .nextSpace:
            try container.encode(Kind.nextSpace, forKey: .kind)
        case .missionControl:
            try container.encode(Kind.missionControl, forKey: .kind)
        case .appExpose:
            try container.encode(Kind.appExpose, forKey: .kind)
        case .launchpad:
            try container.encode(Kind.launchpad, forKey: .kind)
        case .showDesktop:
            try container.encode(Kind.showDesktop, forKey: .kind)
        case .none:
            try container.encode(Kind.none, forKey: .kind)
        case let .custom(keyCode, modifiers):
            try container.encode(Kind.custom, forKey: .kind)
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(modifiers.rawValue, forKey: .modifiers)
        }
    }

    var displayName: String {
        switch self {
        case .prevSpace:
            return "Previous Space"
        case .nextSpace:
            return "Next Space"
        case .missionControl:
            return "Mission Control"
        case .appExpose:
            return "App Expose"
        case .launchpad:
            return "Launchpad"
        case .showDesktop:
            return "Show Desktop"
        case let .custom(keyCode, modifiers):
            let parts = modifierNames(for: modifiers)
            let modifiersDescription = parts.isEmpty ? "No modifiers" : parts.joined(separator: "+")
            return "Custom (key \(keyCode), \(modifiersDescription))"
        case .none:
            return "None"
        }
    }

    var loggingName: String {
        switch self {
        case .prevSpace:
            return "prevSpace"
        case .nextSpace:
            return "nextSpace"
        case .missionControl:
            return "missionControl"
        case .appExpose:
            return "appExpose"
        case .launchpad:
            return "launchpad"
        case .showDesktop:
            return "showDesktop"
        case .custom:
            return "custom"
        case .none:
            return "none"
        }
    }

    var shortcut: KeyboardShortcut? {
        switch self {
        case .prevSpace:
            return KeyboardShortcut(keyCode: CGKeyCode(kVK_LeftArrow), modifiers: .maskControl)
        case .nextSpace:
            return KeyboardShortcut(keyCode: CGKeyCode(kVK_RightArrow), modifiers: .maskControl)
        case .missionControl:
            return KeyboardShortcut(keyCode: CGKeyCode(kVK_UpArrow), modifiers: .maskControl)
        case .appExpose:
            return KeyboardShortcut(keyCode: CGKeyCode(kVK_DownArrow), modifiers: .maskControl)
        case .launchpad:
            return KeyboardShortcut(keyCode: CGKeyCode(kVK_F4), modifiers: [])
        case .showDesktop:
            return KeyboardShortcut(keyCode: CGKeyCode(kVK_F11), modifiers: [])
        case let .custom(keyCode, modifiers):
            return KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)
        case .none:
            return nil
        }
    }

    var handlesEvent: Bool {
        shortcut != nil
    }

    private func modifierNames(for flags: CGEventFlags) -> [String] {
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("Ctrl") }
        if flags.contains(.maskCommand) { parts.append("Cmd") }
        if flags.contains(.maskAlternate) { parts.append("Opt") }
        if flags.contains(.maskShift) { parts.append("Shift") }
        return parts
    }
}

enum ButtonActionChoice: String, CaseIterable, Identifiable {
    case prevSpace
    case nextSpace
    case missionControl
    case appExpose
    case launchpad
    case showDesktop
    case custom
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .prevSpace:
            return "Previous Space"
        case .nextSpace:
            return "Next Space"
        case .missionControl:
            return "Mission Control"
        case .appExpose:
            return "App Expose"
        case .launchpad:
            return "Launchpad"
        case .showDesktop:
            return "Show Desktop"
        case .custom:
            return "Custom"
        case .none:
            return "None"
        }
    }

    init(action: ButtonAction) {
        switch action {
        case .prevSpace:
            self = .prevSpace
        case .nextSpace:
            self = .nextSpace
        case .missionControl:
            self = .missionControl
        case .appExpose:
            self = .appExpose
        case .launchpad:
            self = .launchpad
        case .showDesktop:
            self = .showDesktop
        case .custom:
            self = .custom
        case .none:
            self = .none
        }
    }

    func makeAction(preserving existingAction: ButtonAction) -> ButtonAction {
        switch self {
        case .prevSpace:
            return .prevSpace
        case .nextSpace:
            return .nextSpace
        case .missionControl:
            return .missionControl
        case .appExpose:
            return .appExpose
        case .launchpad:
            return .launchpad
        case .showDesktop:
            return .showDesktop
        case .none:
            return .none
        case .custom:
            if case let .custom(keyCode, modifiers) = existingAction {
                return .custom(keyCode: keyCode, modifiers: modifiers)
            }
            return .custom(keyCode: CGKeyCode(kVK_LeftArrow), modifiers: .maskControl)
        }
    }
}
