import SwiftUI
import SwiftData

struct InlineHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var expandedId: String?
    @State private var selectedTranscriptions: Set<Transcription> = []
    @State private var showDeleteConfirmation = false
    @State private var isPanelPresented = false
    @State private var panelMode: InlineHistoryPanelMode = .info
    @State private var panelEntryId: String?
    @State private var aiEditDetailEntryId: String?
    @State private var screenContextEntryId: String?
    @State private var displayedEntries: [HistoryEntry] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    @State private var lastTimestamp: Date?
    @State private var isViewCurrentlyVisible = false

    private let exportService = VoiceInkCSVExportService()
    private let pageSize = 20

    @Query(Self.createLatestTranscriptionIndicatorDescriptor()) private var latestTranscriptionIndicator: [Transcription]
    @Query(Self.createLatestAIEditIndicatorDescriptor()) private var latestAIEditIndicator: [AIEditHistoryRecord]

    private static func createLatestTranscriptionIndicatorDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private static func createLatestAIEditIndicatorDescriptor() -> FetchDescriptor<AIEditHistoryRecord> {
        var descriptor = FetchDescriptor<AIEditHistoryRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private var allSelected: Bool {
        !displayedTranscriptionEntries.isEmpty &&
            displayedTranscriptionEntries.allSatisfy { selectedTranscriptions.contains($0) }
    }

    private var displayedTranscriptionEntries: [Transcription] {
        displayedEntries.compactMap(\.transcription)
    }

    private var panelEntry: HistoryEntry? {
        guard let id = panelEntryId else { return nil }
        return displayedEntries.first { $0.id == id }
    }

    private var aiEditDetailRecord: AIEditHistoryRecord? {
        guard let id = aiEditDetailEntryId else { return nil }
        return displayedEntries.first { $0.id == id }?.aiEditRecord
    }

    private var screenContextRecord: AIEditHistoryRecord? {
        guard let id = screenContextEntryId else { return nil }
        return displayedEntries.first { $0.id == id }?.aiEditRecord
    }

    private func openPanel(mode: InlineHistoryPanelMode, entryID: String? = nil) {
        panelMode = mode
        panelEntryId = entryID

        isPanelPresented = true
    }

    private func closePanel() {
        isPanelPresented = false
        panelMode = .info
    }

    private func openAIEditDetail(entryID: String) {
        aiEditDetailEntryId = entryID
    }

    private func openScreenContext(entryID: String) {
        screenContextEntryId = entryID
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()

            if displayedEntries.isEmpty && !isLoading {
                emptyStateView
            } else {
                cardListView
            }

            if !selectedTranscriptions.isEmpty {
                Divider()
                selectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedTranscriptions.isEmpty)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sidePanel(isPresented: .init(
            get: { isPanelPresented },
            set: { newValue in
                if !newValue { closePanel() }
            }
        )) {
            panelContent
        }
        .sheet(isPresented: Binding(
            get: { aiEditDetailEntryId != nil },
            set: { newValue in
                if !newValue { aiEditDetailEntryId = nil }
            }
        )) {
            if let record = aiEditDetailRecord {
                aiEditDetailSheet(record)
            }
        }
        .sheet(isPresented: Binding(
            get: { screenContextEntryId != nil },
            set: { newValue in
                if !newValue { screenContextEntryId = nil }
            }
        )) {
            if let screenContext = screenContextRecord?.sentScreenContext {
                AIEditScreenContextInspectorView(
                    contextText: screenContext,
                    subtitle: "Sent with this AI Edit request"
                )
            }
        }
        .alert("Delete Selected Items?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedTranscriptions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(String(localized: "This action cannot be undone. Are you sure you want to delete \(selectedTranscriptions.count) items?"))
        }
        .onAppear {
            isViewCurrentlyVisible = true
            Task { await loadInitialContent() }
        }
        .onDisappear {
            isViewCurrentlyVisible = false
        }
        .onChange(of: searchText) { _, _ in
            Task {
                resetPagination()
                await loadInitialContent()
            }
        }
        .onChange(of: latestTranscriptionIndicator.first?.id) { oldId, newId in
            guard isViewCurrentlyVisible else { return }
            if newId != oldId {
                Task {
                    resetPagination()
                    await loadInitialContent()
                }
            }
        }
        .onChange(of: latestAIEditIndicator.first?.updatedAt) { oldDate, newDate in
            guard isViewCurrentlyVisible else { return }
            if newDate != oldDate {
                Task {
                    resetPagination()
                    await loadInitialContent()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiEditHistoryChanged)) { _ in
            guard isViewCurrentlyVisible else { return }
            Task {
                resetPagination()
                await loadInitialContent()
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                TextField("Search history...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(AppTheme.Surface.card)
            )
            .frame(maxWidth: .infinity)

            AppIconButton(
                systemName: "gearshape",
                help: "History settings",
                size: 30,
                iconSize: 13,
                cornerRadius: AppTheme.Radius.pill
            ) {
                openPanel(mode: .historySettings)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var selectionBar: some View {
        HStack(spacing: 16) {
            Text(String(format: String(localized: "%lld selected"), Int64(selectedTranscriptions.count)))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            Button(action: {
                openPanel(mode: .analysis)
            }) {
                Label("Analyze", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Button(action: {
                exportService.exportTranscriptionsToCSV(transcriptions: Array(selectedTranscriptions))
            }) {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Button(action: { showDeleteConfirmation = true }) {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(AppTheme.Status.error.opacity(0.80))

            Divider()
                .frame(height: 16)

            if allSelected {
                Button("Deselect All") {
                    selectedTranscriptions.removeAll()
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            } else {
                Button("Select All") {
                    Task { await selectAllTranscriptions() }
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(
            AppTheme.Surface.window
                .shadow(color: Color.black.opacity(0.1), radius: 3, y: -2)
        )
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty ? "No history yet" : "No results found")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            Text(searchText.isEmpty ? "Your transcription and AI Edit history will appear here" : "Try a different search term")
                .font(.system(size: 13))
                .foregroundColor(.secondary.opacity(0.8))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Card List

    private var cardListView: some View {
        Form {
            ForEach(displayedEntries) { entry in
                Section {
                    HistoryCardRow(
                        entry: entry,
                        isExpanded: expandedId == entry.id,
                        isChecked: entry.transcription.map { selectedTranscriptions.contains($0) } ?? false,
                        onToggleExpand: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandedId = expandedId == entry.id ? nil : entry.id
                            }
                        },
                        onToggleCheck: entry.transcription.map { transcription in
                            { toggleSelection(transcription) }
                        },
                        onShowInfo: {
                            openPanel(mode: .info, entryID: entry.id)
                        },
                        onShowDebug: entry.aiEditRecord == nil ? nil : {
                            openAIEditDetail(entryID: entry.id)
                        },
                        onShowScreenContext: entry.aiEditRecord?.sentScreenContext == nil ? nil : {
                            openScreenContext(entryID: entry.id)
                        }
                    )
                }
            }

            if hasMoreContent {
                Section {
                    Button(action: {
                        Task { await loadMoreContent() }
                    }) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView().controlSize(.small)
                            }
                            Text(isLoading ? "Loading..." : "Load More")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Side Panel

    private func aiEditDetailSheet(_ record: AIEditHistoryRecord) -> some View {
        VStack(spacing: 0) {
            AppPanelHeader(title: "AI Edit Details", onClose: { aiEditDetailEntryId = nil })

            AIEditHistoryDetailView(record: record)
        }
        .frame(minWidth: 760, idealWidth: 940, minHeight: 620, idealHeight: 760)
        .background(SidePanelBackground())
    }

    @ViewBuilder
    private var panelContent: some View {
        switch panelMode {
        case .info:
            infoPanelContent
        case .analysis:
            PerformanceAnalysisPanelView(
                transcriptions: Array(selectedTranscriptions),
                onClose: {
                    closePanel()
                }
            )
            .id(selectedTranscriptions.count)
        case .historySettings:
            HistorySettingsPanel(onClose: closePanel)
        }
    }

    private var infoPanelContent: some View {
        VStack(spacing: 0) {
            AppPanelHeader(title: "Info", onClose: closePanel)

            if let entry = panelEntry {
                switch entry {
                case .transcription(let transcription):
                TranscriptionInfoPanel(transcription: transcription)
                    .id(transcription.id)
                case .aiEdit(let record):
                    AIEditHistoryInfoPanel(record: record)
                        .id(record.id)
                }
            } else {
                Spacer()
            }
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func loadInitialContent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            lastTimestamp = nil
            let page = try HistoryFetchService.fetchPage(
                modelContext: modelContext,
                searchText: searchText,
                pageSize: pageSize
            )
            displayedEntries = page.entries
            lastTimestamp = page.lastTimestamp
            hasMoreContent = page.hasMore
        } catch {
            print("Error loading history: \(error)")
        }
    }

    @MainActor
    private func loadMoreContent() async {
        guard !isLoading, hasMoreContent, let lastTimestamp = lastTimestamp else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let page = try HistoryFetchService.fetchPage(
                modelContext: modelContext,
                searchText: searchText,
                after: lastTimestamp,
                pageSize: pageSize
            )
            displayedEntries.append(contentsOf: page.entries)
            self.lastTimestamp = page.lastTimestamp
            hasMoreContent = page.hasMore
        } catch {
            print("Error loading more history: \(error)")
        }
    }

    @MainActor
    private func resetPagination() {
        displayedEntries = []
        lastTimestamp = nil
        hasMoreContent = true
        isLoading = false
    }

    // MARK: - Selection & Deletion

    private func toggleSelection(_ transcription: Transcription) {
        if selectedTranscriptions.contains(transcription) {
            selectedTranscriptions.remove(transcription)
        } else {
            selectedTranscriptions.insert(transcription)
        }
    }

    private func performDeletion(for transcription: Transcription) {
        if let urlString = transcription.audioFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("Error deleting audio file: \(error.localizedDescription)")
            }
        }

        let entryId = HistoryEntry.transcription(transcription).id
        if expandedId == entryId {
            expandedId = nil
        }
        if panelEntryId == entryId {
            panelEntryId = nil
            closePanel()
        }

        selectedTranscriptions.remove(transcription)
        modelContext.delete(transcription)
    }

    private func deleteSelectedTranscriptions() {
        for transcription in selectedTranscriptions {
            performDeletion(for: transcription)
        }
        selectedTranscriptions.removeAll()

        Task {
            do {
                try modelContext.save()
                NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
                await loadInitialContent()
            } catch {
                print("Error saving deletion: \(error.localizedDescription)")
                await loadInitialContent()
            }
        }
    }

    private func selectAllTranscriptions() async {
        do {
            var allDescriptor = FetchDescriptor<Transcription>()
            if !searchText.isEmpty {
                allDescriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.text.localizedStandardContains(searchText) ||
                    (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
                }
            }
            allDescriptor.propertiesToFetch = [\.id]
            let allTranscriptions = try modelContext.fetch(allDescriptor)
            let visibleIds = Set(displayedTranscriptionEntries.map { $0.id })

            await MainActor.run {
                selectedTranscriptions = Set(displayedTranscriptionEntries)

                for transcription in allTranscriptions {
                    if !visibleIds.contains(transcription.id) {
                        selectedTranscriptions.insert(transcription)
                    }
                }
            }
        } catch {
            print("Error selecting all transcriptions: \(error)")
        }
    }
}

private enum InlineHistoryPanelMode {
    case info
    case analysis
    case historySettings
}

// MARK: - History Card Row

private struct HistoryCardRow: View {
    let entry: HistoryEntry
    let isExpanded: Bool
    let isChecked: Bool
    let onToggleExpand: () -> Void
    let onToggleCheck: (() -> Void)?
    let onShowInfo: () -> Void
    let onShowDebug: (() -> Void)?
    let onShowScreenContext: (() -> Void)?

    @State private var selectedTab: TranscriptionTab = .original

    private var displayText: String {
        switch entry {
        case .transcription(let transcription):
            switch selectedTab {
            case .original:
                return transcription.text
            case .enhanced:
                return transcription.enhancedText ?? ""
            }
        case .aiEdit(let record):
            return record.generatedText
        }
    }

    private var hasAudioFile: Bool {
        guard let transcription = entry.transcription else { return false }
        if let urlString = transcription.audioFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if let onToggleCheck {
                    Toggle("", isOn: Binding(
                        get: { isChecked },
                        set: { _ in onToggleCheck() }
                    ))
                    .toggleStyle(CircularCheckboxStyle())
                    .labelsHidden()
                } else {
                    Image(systemName: entry.kindSystemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(entry.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        if entry.aiEditRecord != nil {
                            Text(entry.kindLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(AppTheme.Surface.card)
                                )
                                .foregroundColor(.secondary)
                        }
                    }

                    if !isExpanded {
                        Text(entry.previewText)
                            .font(.system(size: 13))
                            .lineLimit(2)
                            .foregroundColor(.primary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
            }
            .contentShape(Rectangle())
            .onTapGesture { onToggleExpand() }

            if isExpanded {
                expandedContent
                    .padding(.top, 10)
            }
        }
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch entry {
            case .transcription(let transcription):
                transcriptionExpandedContent(transcription)
            case .aiEdit(let record):
                aiEditExpandedContent(record)
            }
        }
    }

    @ViewBuilder
    private func transcriptionExpandedContent(_ transcription: Transcription) -> some View {
        if transcription.enhancedText != nil {
            HStack(spacing: 4) {
                ForEach(TranscriptionTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(LocalizedStringKey(tab.rawValue))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tab ? AppTheme.Surface.controlActive : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }

        ScrollView {
            MarkdownContentView(
                displayText,
                fontSize: 14,
                foregroundColor: AppTheme.Text.primary
            )
        }
        .frame(maxHeight: 350)
        .hoverCopyButton(textToCopy: displayText)

        if hasAudioFile, let urlString = transcription.audioFileURL,
           let url = URL(string: urlString) {
            Divider()
            AudioPlayerView(url: url, transcription: transcription, onInfoTap: onShowInfo)
                .padding(.vertical, 4)
        } else {
            infoButtonRow
        }
    }

    private func aiEditExpandedContent(_ record: AIEditHistoryRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(record.mode.displayName, systemImage: record.outcome.systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Instruction")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(record.instruction)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
            }

            ScrollView {
                MarkdownContentView(
                    record.generatedText,
                    fontSize: 14,
                    foregroundColor: AppTheme.Text.primary
                )
            }
            .frame(maxHeight: 350)
            .hoverCopyButton(textToCopy: record.generatedText)

            if onShowDebug != nil || onShowScreenContext != nil {
                aiEditDebugButtonRow
            }

            infoButtonRow
        }
    }

    private var aiEditDebugButtonRow: some View {
        HStack(spacing: 8) {
            if let onShowDebug {
                Button(action: onShowDebug) {
                    Label("Prompt / payload", systemImage: "curlybraces")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("View AI Edit prompt and payload")
            }

            if let onShowScreenContext {
                Button(action: onShowScreenContext) {
                    Label("Screen context", systemImage: "rectangle.on.rectangle")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.borderless)
                .help("View sent screen context")
            }

            Spacer()
        }
    }

    private var infoButtonRow: some View {
        HStack {
            Spacer()
            Button(action: onShowInfo) {
                Image(systemName: "info.circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("View details")
        }
    }
}
