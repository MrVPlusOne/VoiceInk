import Foundation

enum AIUserPreferences {
    // Keep the original key so existing preferences and backups continue to work.
    static let userDefaultsKey = "UniversalAIEditUserPreferences"

    static func promptBlock(_ text: String?) -> String? {
        guard let text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return "<user_preferences>\n\(text)\n</user_preferences>"
    }
}

enum AIEnhancementPromptBuilder {
    static func userMessage(
        text: String,
        userPreferences: String?,
        screenshotMetadata: String? = nil
    ) -> String {
        var parts = [
            """
            \n<USER_MESSAGE>
            \(text)
            </USER_MESSAGE>
            """
        ]

        if let userPreferences = AIUserPreferences.promptBlock(userPreferences) {
            parts.append(userPreferences)
        }

        if let screenshotMetadata {
            parts.append("""
            <ATTACHED_SCREENSHOT_CONTEXT>
            \(screenshotMetadata)
            </ATTACHED_SCREENSHOT_CONTEXT>
            """)
        }

        return parts.joined(separator: "\n\n")
    }
}
