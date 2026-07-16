import Foundation

struct UniversalAIEditPromptTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var content: String
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        content: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.label = label
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum UniversalAIEditPromptTemplateStore {
    static let userDefaultsKey = "UniversalAIEditPromptTemplates"

    static func load(defaults: UserDefaults = .standard) -> [UniversalAIEditPromptTemplate] {
        guard let data = defaults.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([UniversalAIEditPromptTemplate].self, from: data) else {
            return []
        }

        return normalized(decoded)
    }

    static func save(_ templates: [UniversalAIEditPromptTemplate], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(normalized(templates)) else { return }
        defaults.set(data, forKey: userDefaultsKey)
    }

    private static func normalized(_ templates: [UniversalAIEditPromptTemplate]) -> [UniversalAIEditPromptTemplate] {
        templates.compactMap { template in
            let label = template.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty,
                  !template.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            var normalizedTemplate = template
            normalizedTemplate.label = label
            return normalizedTemplate
        }
    }
}

struct UniversalAIEditPromptTemplateInsertionResult: Equatable {
    let text: String
    let caretLocation: Int
}

enum UniversalAIEditPromptTemplateInsertionStrategy {
    case atEditorSelection
    case replacingInstruction
}

enum UniversalAIEditPromptTemplateInsertion {
    static func insert(
        _ templateContent: String,
        into instruction: String,
        selectedRange: NSRange?,
        strategy: UniversalAIEditPromptTemplateInsertionStrategy = .atEditorSelection
    ) -> UniversalAIEditPromptTemplateInsertionResult {
        let nsInstruction = instruction as NSString
        let instructionLength = nsInstruction.length
        if strategy == .replacingInstruction {
            return UniversalAIEditPromptTemplateInsertionResult(
                text: templateContent,
                caretLocation: (templateContent as NSString).length
            )
        }

        let safeRange = clampedRange(selectedRange, instructionLength: instructionLength)

        guard let stringRange = Range(safeRange, in: instruction) else {
            let text = instruction + templateContent
            return UniversalAIEditPromptTemplateInsertionResult(
                text: text,
                caretLocation: instructionLength + (templateContent as NSString).length
            )
        }

        let text = instruction.replacingCharacters(in: stringRange, with: templateContent)
        return UniversalAIEditPromptTemplateInsertionResult(
            text: text,
            caretLocation: safeRange.location + (templateContent as NSString).length
        )
    }

    private static func clampedRange(_ selectedRange: NSRange?, instructionLength: Int) -> NSRange {
        guard let selectedRange,
              selectedRange.location != NSNotFound else {
            return NSRange(location: instructionLength, length: 0)
        }

        let location = min(max(0, selectedRange.location), instructionLength)
        let maxLength = instructionLength - location
        let length = min(max(0, selectedRange.length), maxLength)
        return NSRange(location: location, length: length)
    }
}

enum UniversalAIEditPromptTemplateMouseActivation {
    static func shouldActivate(clickCount: Int) -> Bool {
        clickCount <= 1
    }
}

enum UniversalAIEditPromptTemplateGenerationActivation {
    static func canActivate(phase: UniversalAIEditPhase) -> Bool {
        !phase.isBusy
    }
}

enum UniversalAIEditPromptTemplateShortcut {
    static func number(forButtonIndex index: Int) -> Int? {
        guard index >= 0, index < 10 else { return nil }
        return index == 9 ? 10 : index + 1
    }

    static func displayNumber(forButtonIndex index: Int) -> String? {
        guard let number = number(forButtonIndex: index) else { return nil }
        return number == 10 ? "0" : "\(number)"
    }

    static func number(forKeyCode keyCode: UInt16) -> Int? {
        switch keyCode {
        case 18: return 1
        case 19: return 2
        case 20: return 3
        case 21: return 4
        case 23: return 5
        case 22: return 6
        case 26: return 7
        case 28: return 8
        case 25: return 9
        case 29: return 10
        default: return nil
        }
    }
}
