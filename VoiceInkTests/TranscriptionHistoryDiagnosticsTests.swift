import Foundation
import SwiftData
import Testing
@testable import VoiceInk

@MainActor
struct TranscriptionHistoryDiagnosticsTests {
    @Test func persistsRecognitionAndEnhancementMetadataTogether() throws {
        let container = try ModelContainer(for: Transcription.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let writer = ModelContext(container)
        let record = Transcription(text: "einsum", duration: 1,
            aiRequestSystemMessage: "System instructions\n<CURRENT_WINDOW_CONTEXT>Enhancement screen</CURRENT_WINDOW_CONTEXT>",
            aiRequestUserMessage: "<USER_MESSAGE>einsum</USER_MESSAGE>")
        let diagnostics = TranscriptionDiagnosticsRecorder()
        diagnostics.record(TranscriptionRequestDiagnostics(
            model: "custom-speech", provider: "Custom", transport: "File", language: "en",
            prompt: "Prompt plus recognition screen", recognitionContext: "Recognition screen", notes: "Test"
        ))
        record.transcriptionRequestDiagnosticsJSON = diagnostics.encodedRequests
        writer.insert(record)
        try writer.save()

        let reader = ModelContext(container)
        let saved = try #require(reader.fetch(FetchDescriptor<Transcription>()).first)
        #expect(saved.transcriptionRequestDiagnostics == diagnostics.requests)
        #expect(saved.aiRequestUserMessage == "<USER_MESSAGE>einsum</USER_MESSAGE>")
        #expect(saved.screenContextForInspection.contains("Recognition screen"))
        #expect(saved.screenContextForInspection.contains("Enhancement screen"))
    }

    @Test func oldRecordDoesNotInventMetadataFromCurrentSettings() {
        let record = Transcription(text: "Old record", duration: 1)
        #expect(record.transcriptionRequestDiagnostics == nil)
        #expect(record.screenContextForInspection.contains("cannot be reconstructed"))
        record.transcriptionRequestDiagnosticsJSON = "[]"
        #expect(record.transcriptionRequestDiagnostics == [])
        #expect(record.screenContextForInspection.contains("No screen context"))
    }

    @Test func requestContextRecordsOnlyExplicitlySuppliedRecognitionText() {
        let model = CustomCloudModel(name: "custom", displayName: "Custom", description: "Test",
            apiEndpoint: "https://example.invalid/transcriptions", modelName: "actual-model")
        var context = TranscriptionRequestContext(language: "en", prompt: "Base prompt", recognitionContext: "Screen hint")
        let diagnostics = TranscriptionDiagnosticsRecorder()
        context.diagnostics = diagnostics
        context.recordRequest(model: model, transport: "Streaming", notes: "No prompt sent")
        context.recordRequest(model: model, prompt: context.promptWithRecognitionContext,
            recognitionContext: context.recognitionContext, notes: "File fallback")
        #expect(diagnostics.requests[0].prompt == nil)
        #expect(diagnostics.requests[0].recognitionContext == nil)
        #expect(diagnostics.requests[1].model == "actual-model")
        #expect(diagnostics.requests[1].prompt == "Base prompt\n\nScreen hint")
    }

    @Test func cancellationKeepsAttemptedRequestMetadata() {
        let record = Transcription(text: "Draft", duration: 1,
            aiRequestSystemMessage: "Attempted system instructions", aiRequestUserMessage: "Attempted payload")
        record.transcriptionRequestDiagnosticsJSON = "[]"
        record.markAsCanceledTranscription()
        #expect(record.aiRequestSystemMessage == "Attempted system instructions")
        #expect(record.aiRequestUserMessage == "Attempted payload")
        #expect(record.transcriptionRequestDiagnosticsJSON == "[]")
    }
}
