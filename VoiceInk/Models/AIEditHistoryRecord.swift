import Foundation
import SwiftData

enum AIEditHistoryOutcome: String, Codable, CaseIterable {
    case generated
    case copied
    case applied
    case discarded

    var displayName: String {
        switch self {
        case .generated:
            return String(localized: "Generated")
        case .copied:
            return String(localized: "Copied")
        case .applied:
            return String(localized: "Applied")
        case .discarded:
            return String(localized: "Discarded")
        }
    }

    var systemImage: String {
        switch self {
        case .generated:
            return "sparkles"
        case .copied:
            return "doc.on.doc"
        case .applied:
            return "checkmark.circle"
        case .discarded:
            return "xmark.circle"
        }
    }
}

@Model
final class AIEditHistoryRecord {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var updatedAt: Date = Date()
    var instruction: String = ""
    var modeRawValue: String = UniversalAIEditMode.insertNew.rawValue
    var sourceText: String?
    var generatedText: String = ""
    var providerName: String = ""
    var modelName: String = ""
    var generationDuration: TimeInterval = 0
    var targetAppName: String?
    var targetBundleIdentifier: String?
    var targetProcessIdentifier: Int?
    var targetWindowTitle: String?
    var targetWindowFrameX: Double?
    var targetWindowFrameY: Double?
    var targetWindowFrameWidth: Double?
    var targetWindowFrameHeight: Double?
    var outcomeRawValue: String = AIEditHistoryOutcome.generated.rawValue
    var outcomeNote: String?
    var aiRequestSystemMessage: String?
    var aiRequestUserMessage: String?

    init(
        instruction: String,
        mode: UniversalAIEditMode,
        sourceText: String? = nil,
        generatedText: String,
        providerName: String,
        modelName: String,
        generationDuration: TimeInterval,
        target: UniversalAIEditTargetSnapshot,
        outcome: AIEditHistoryOutcome = .generated,
        outcomeNote: String? = nil,
        aiRequestSystemMessage: String? = nil,
        aiRequestUserMessage: String? = nil,
        timestamp: Date = Date()
    ) {
        id = UUID()
        self.timestamp = timestamp
        updatedAt = timestamp
        self.instruction = instruction
        modeRawValue = mode.rawValue
        self.sourceText = Self.normalized(sourceText)
        self.generatedText = generatedText
        self.providerName = providerName
        self.modelName = modelName
        self.generationDuration = generationDuration
        targetAppName = target.appName
        targetBundleIdentifier = target.bundleIdentifier
        targetProcessIdentifier = target.processIdentifier.map(Int.init)
        targetWindowTitle = target.focusedWindowTitle
        targetWindowFrameX = target.focusedWindowFrame.map { Double($0.origin.x) }
        targetWindowFrameY = target.focusedWindowFrame.map { Double($0.origin.y) }
        targetWindowFrameWidth = target.focusedWindowFrame.map { Double($0.size.width) }
        targetWindowFrameHeight = target.focusedWindowFrame.map { Double($0.size.height) }
        outcomeRawValue = outcome.rawValue
        self.outcomeNote = Self.normalized(outcomeNote)
        self.aiRequestSystemMessage = Self.normalized(aiRequestSystemMessage)
        self.aiRequestUserMessage = Self.normalized(aiRequestUserMessage)
    }

    var mode: UniversalAIEditMode {
        UniversalAIEditMode(rawValue: modeRawValue) ?? .insertNew
    }

    var outcome: AIEditHistoryOutcome {
        AIEditHistoryOutcome(rawValue: outcomeRawValue) ?? .generated
    }

    var targetDisplayName: String {
        targetAppName ?? String(localized: "Active app")
    }

    var targetWindowFrameDescription: String? {
        guard let x = targetWindowFrameX,
              let y = targetWindowFrameY,
              let width = targetWindowFrameWidth,
              let height = targetWindowFrameHeight else {
            return nil
        }

        return "\(Int(x)), \(Int(y)) - \(Int(width)) x \(Int(height))"
    }

    var fullRequestText: String {
        var parts: [String] = []
        if let system = aiRequestSystemMessage, !system.isEmpty {
            parts.append("System Prompt:\n\(system)")
        }
        if let user = aiRequestUserMessage, !user.isEmpty {
            parts.append("User Payload:\n\(user)")
        }
        return parts.joined(separator: "\n\n")
    }

    func recordOutcome(_ outcome: AIEditHistoryOutcome, note: String? = nil) {
        outcomeRawValue = outcome.rawValue
        outcomeNote = Self.normalized(note)
        updatedAt = Date()
    }

    private static func normalized(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
