import Foundation

/// Keeps short UI labels separate from the complete, copyable provider response.
struct APIErrorPresentation: Equatable, Sendable {
    let title: String
    let guidance: String
    let details: String

    init(message: String) {
        title = String(localized: "Something went wrong")
        guidance = Self.redact(message)
        details = Self.redact(message)
    }

    init(statusCode: Int, responseBody: String) {
        let object = (try? JSONSerialization.jsonObject(with: Data(responseBody.utf8))) as? [String: Any]
        let error = (object?["error"] as? [String: Any]) ?? object
        let code = (error?["code"] as? String)?.lowercased() ?? ""
        let type = (error?["type"] as? String)?.lowercased() ?? ""

        // Prefer the specific code over the broad insufficient_quota type.
        switch (statusCode, code) {
        case (429, "credit_balance_exhausted"):
            title = String(localized: "API credits exhausted")
            guidance = String(localized: "The API account has no credits remaining. Check the provider's billing settings before trying again.")
        case (429, "project_spend_limit_exceeded"):
            title = String(localized: "Project spending limit reached")
            guidance = String(localized: "Check the spending limit for the API key's project in the provider's settings. Retrying now will not restore access.")
        case (429, "organization_spend_limit_exceeded"), (429, "billing_hard_limit_reached"):
            title = String(localized: "API spending limit reached")
            guidance = String(localized: "The API account has reached its spending limit. Check the provider's billing and limit settings before trying again.")
        case (429, "organization_usage_limit_exceeded"):
            title = String(localized: "API usage limit reached")
            guidance = String(localized: "The organization has reached its approved API usage limit. Contact the provider or your organization administrator.")
        case (429, _) where code == "insufficient_quota" || type == "insufficient_quota":
            title = String(localized: "API quota exhausted")
            guidance = String(localized: "Check the API account's credits, billing, and usage limits. A saved API key does not guarantee available quota; retrying will not resolve a billing limit.")
        case (429, _) where ["rate_limit_exceeded", "rate_limit_error", "slow_down"].contains(code)
            || ["rate_limit_exceeded", "rate_limit_error"].contains(type):
            title = String(localized: "Too many API requests")
            guidance = String(localized: "The provider is temporarily limiting requests. Wait before trying again; see the provider's message below for any suggested delay.")
        case (429, _):
            title = String(localized: "API limit reached")
            guidance = String(localized: "The provider returned HTTP 429. This can mean a temporary rate limit or an account quota limit. Check the full response below before retrying.")
        case (401, _):
            title = String(localized: "API authentication failed")
            guidance = String(localized: "Check that the configured API key is correct, active, and belongs to the intended account.")
        case (403, _):
            title = String(localized: "API access denied")
            guidance = String(localized: "Check the API key's permissions and the account's access to the selected model.")
        case (404, _):
            title = String(localized: "API model or endpoint unavailable")
            guidance = String(localized: "Check the selected model, endpoint, and your account's model access.")
        case (500...599, _):
            title = String(localized: "API service unavailable")
            guidance = String(localized: "The provider could not complete the request. Try again later or check the provider's service status.")
        default:
            title = String(localized: "API request failed")
            guidance = String(localized: "The provider rejected the request. See the full response below for the reason.")
        }

        let formattedBody: String
        if let object, let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            formattedBody = json
        } else {
            formattedBody = responseBody.isEmpty ? String(localized: "No response body was provided.") : responseBody
        }
        details = "HTTP \(statusCode)\n\n\(Self.redact(formattedBody))"
    }

    var copyableText: String {
        "\(title)\n\n\(guidance)\n\n\(details)"
    }

    private static func redact(_ text: String) -> String {
        // Providers sometimes echo credentials in authentication errors.
        text.replacingOccurrences(of: #"(?i)\bsk-[a-z0-9_\-*]{8,}"#, with: "[redacted API key]", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bBearer\s+[a-z0-9._~+/=-]+"#, with: "Bearer [redacted]", options: .regularExpression)
    }
}
