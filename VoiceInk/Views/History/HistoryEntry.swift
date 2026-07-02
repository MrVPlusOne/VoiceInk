import Foundation

enum HistoryEntry: Identifiable, Hashable {
    case transcription(Transcription)
    case aiEdit(AIEditHistoryRecord)

    var id: String {
        switch self {
        case .transcription(let transcription):
            return "transcription-\(transcription.id.uuidString)"
        case .aiEdit(let record):
            return "ai-edit-\(record.id.uuidString)"
        }
    }

    var timestamp: Date {
        switch self {
        case .transcription(let transcription):
            return transcription.timestamp
        case .aiEdit(let record):
            return record.timestamp
        }
    }

    var previewText: String {
        switch self {
        case .transcription(let transcription):
            return transcription.enhancedText ?? transcription.text
        case .aiEdit(let record):
            return record.generatedText
        }
    }

    var kindLabel: String {
        switch self {
        case .transcription:
            return String(localized: "Transcription")
        case .aiEdit:
            return String(localized: "AI Edit")
        }
    }

    var kindSystemImage: String {
        switch self {
        case .transcription:
            return "doc.text"
        case .aiEdit:
            return "wand.and.sparkles"
        }
    }

    var transcription: Transcription? {
        if case .transcription(let transcription) = self {
            return transcription
        }
        return nil
    }

    var aiEditRecord: AIEditHistoryRecord? {
        if case .aiEdit(let record) = self {
            return record
        }
        return nil
    }
}
