import Foundation
import SwiftData

struct HistoryPage {
    let entries: [HistoryEntry]
    let hasMore: Bool
    let lastTimestamp: Date?
}

enum HistoryFetchService {
    static func fetchPage(
        modelContext: ModelContext,
        searchText: String,
        after timestamp: Date? = nil,
        pageSize: Int
    ) throws -> HistoryPage {
        let transcriptions = try modelContext.fetch(
            transcriptionDescriptor(searchText: searchText, after: timestamp, pageSize: pageSize)
        )
        let aiEdits = try modelContext.fetch(
            aiEditDescriptor(searchText: searchText, after: timestamp, pageSize: pageSize)
        )

        let entries = (
            transcriptions.map(HistoryEntry.transcription) +
            aiEdits.map(HistoryEntry.aiEdit)
        )
        .sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id > rhs.id
            }
            return lhs.timestamp > rhs.timestamp
        }
        .prefix(pageSize)

        let pageEntries = Array(entries)
        let hasMore = pageEntries.count == pageSize &&
            (transcriptions.count == pageSize || aiEdits.count == pageSize)

        return HistoryPage(
            entries: pageEntries,
            hasMore: hasMore,
            lastTimestamp: pageEntries.last?.timestamp
        )
    }

    private static func transcriptionDescriptor(
        searchText: String,
        after timestamp: Date?,
        pageSize: Int
    ) -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )

        if let timestamp {
            if searchText.isEmpty {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.timestamp < timestamp
                }
            } else {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    (transcription.text.localizedStandardContains(searchText) ||
                    (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)) &&
                    transcription.timestamp < timestamp
                }
            }
        } else if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Transcription> { transcription in
                transcription.text.localizedStandardContains(searchText) ||
                (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
            }
        }

        descriptor.fetchLimit = pageSize
        return descriptor
    }

    private static func aiEditDescriptor(
        searchText: String,
        after timestamp: Date?,
        pageSize: Int
    ) -> FetchDescriptor<AIEditHistoryRecord> {
        var descriptor = FetchDescriptor<AIEditHistoryRecord>(
            sortBy: [SortDescriptor(\AIEditHistoryRecord.timestamp, order: .reverse)]
        )

        if let timestamp {
            if searchText.isEmpty {
                descriptor.predicate = #Predicate<AIEditHistoryRecord> { record in
                    record.timestamp < timestamp
                }
            } else {
                descriptor.predicate = #Predicate<AIEditHistoryRecord> { record in
                    (record.instruction.localizedStandardContains(searchText) ||
                    (record.sourceText?.localizedStandardContains(searchText) ?? false) ||
                    record.generatedText.localizedStandardContains(searchText)) &&
                    record.timestamp < timestamp
                }
            }
        } else if !searchText.isEmpty {
            descriptor.predicate = #Predicate<AIEditHistoryRecord> { record in
                record.instruction.localizedStandardContains(searchText) ||
                (record.sourceText?.localizedStandardContains(searchText) ?? false) ||
                record.generatedText.localizedStandardContains(searchText)
            }
        }

        descriptor.fetchLimit = pageSize
        return descriptor
    }
}
