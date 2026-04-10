import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    private struct StoredMapping: Codable {
        let buttonNumber: Int
        let action: ButtonAction
    }

    private enum Keys {
        static let enabled = "enabled"
        static let swapButtons = "swapButtons"
        static let buttonMappings = "buttonMappings"
    }

    static let shared = AppModel()

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.enabled) }
    }

    @Published var swapButtons: Bool {
        didSet { defaults.set(swapButtons, forKey: Keys.swapButtons) }
    }

    @Published private(set) var buttonMappings: [Int: ButtonAction]
    @Published private(set) var detectedButtons: Set<Int> = []
    @Published private(set) var lastObservedButton: Int?
    @Published private(set) var learnedButtonNumber: Int?
    @Published var isLearningButton = false
    @Published private(set) var warningMessage: String?

    private let defaults: UserDefaults
    private var highlightResetWorkItem: DispatchWorkItem?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        swapButtons = defaults.object(forKey: Keys.swapButtons) as? Bool ?? false
        buttonMappings = Self.loadMappings(from: defaults) ?? Self.defaultMappings
    }

    var visibleButtons: [Int] {
        Set(buttonMappings.keys).union(detectedButtons).sorted()
    }

    func action(for buttonNumber: Int) -> ButtonAction {
        buttonMappings[buttonNumber] ?? ButtonAction.none
    }

    func effectiveAction(forPhysicalButton buttonNumber: Int) -> ButtonAction {
        action(for: logicalButtonNumber(forPhysicalButton: buttonNumber))
    }

    func setAction(_ action: ButtonAction, for buttonNumber: Int) {
        guard AppEnvironment.supportedButtonRange.contains(buttonNumber) else { return }
        buttonMappings[buttonNumber] = action
        persistMappings()
    }

    @discardableResult
    func addButton() -> Int? {
        guard let buttonNumber = AppEnvironment.supportedButtonRange.first(where: { buttonMappings[$0] == nil && !detectedButtons.contains($0) }) else {
            return nil
        }

        buttonMappings[buttonNumber] = ButtonAction.none
        persistMappings()
        return buttonNumber
    }

    func removeButton(_ buttonNumber: Int) {
        buttonMappings.removeValue(forKey: buttonNumber)
        detectedButtons.remove(buttonNumber)
        if lastObservedButton == buttonNumber {
            lastObservedButton = nil
        }
        persistMappings()
    }

    func beginLearningButton() {
        isLearningButton = true
    }

    func cancelLearningButton() {
        isLearningButton = false
    }

    @discardableResult
    func captureLearnedButton(_ buttonNumber: Int) -> Bool {
        guard isLearningButton, AppEnvironment.supportedButtonRange.contains(buttonNumber) else {
            return false
        }

        isLearningButton = false
        learnedButtonNumber = buttonNumber
        detectedButtons.insert(buttonNumber)
        if buttonMappings[buttonNumber] == nil {
            buttonMappings[buttonNumber] = ButtonAction.none
            persistMappings()
        }
        pulseHighlight(for: buttonNumber)
        return true
    }

    func recordObservedButton(_ buttonNumber: Int) {
        guard AppEnvironment.supportedButtonRange.contains(buttonNumber) else { return }
        detectedButtons.insert(buttonNumber)
        pulseHighlight(for: buttonNumber)
    }

    func setWarning(_ message: String?) {
        warningMessage = message
    }

    private func logicalButtonNumber(forPhysicalButton buttonNumber: Int) -> Int {
        guard swapButtons else { return buttonNumber }

        switch buttonNumber {
        case 3:
            return 4
        case 4:
            return 3
        default:
            return buttonNumber
        }
    }

    // Swift 6 migration: replace DispatchWorkItem with Task { @MainActor in }
    // once the deployment floor moves to macOS 14+ (for MainActor.assumeIsolated).
    private func pulseHighlight(for buttonNumber: Int) {
        lastObservedButton = buttonNumber
        highlightResetWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.lastObservedButton == buttonNumber else { return }
            self.lastObservedButton = nil
        }

        highlightResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: workItem)
    }

    private func persistMappings() {
        let records = buttonMappings
            .filter { AppEnvironment.supportedButtonRange.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { StoredMapping(buttonNumber: $0.key, action: $0.value) }

        let encoder = JSONEncoder()
        if let data = try? encoder.encode(records) {
            defaults.set(data, forKey: Keys.buttonMappings)
        }
    }

    private static func loadMappings(from defaults: UserDefaults) -> [Int: ButtonAction]? {
        guard let data = defaults.data(forKey: Keys.buttonMappings) else {
            return nil
        }

        let decoder = JSONDecoder()
        guard let records = try? decoder.decode([StoredMapping].self, from: data) else {
            return nil
        }

        var mappings: [Int: ButtonAction] = [:]
        for record in records where AppEnvironment.supportedButtonRange.contains(record.buttonNumber) {
            mappings[record.buttonNumber] = record.action
        }

        return mappings.isEmpty ? nil : mappings
    }

    private static let defaultMappings: [Int: ButtonAction] = [
        3: .prevSpace,
        4: .nextSpace
    ]
}
