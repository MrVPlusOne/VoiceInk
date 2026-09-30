import Foundation

enum EnhancementModelSelection {
    // Presets are suggestions for providers that accept a model ID directly.
    // Configured custom endpoints still need a known model to resolve their credentials.
    static func resolve(
        _ configuredModel: String?,
        availableModels: [String],
        fallback: String,
        allowsCustom: Bool
    ) -> String {
        guard let configuredModel,
              !configuredModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              allowsCustom || availableModels.isEmpty || availableModels.contains(configuredModel) else {
            return fallback
        }
        return configuredModel
    }
}
