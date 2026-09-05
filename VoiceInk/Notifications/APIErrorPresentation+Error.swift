import Foundation
import LLMkit

extension APIErrorPresentation {
    init(error: Error) {
        if let cloudError = error as? CloudTranscriptionError,
           case .apiRequestFailed(let status, let body) = cloudError {
            self.init(statusCode: status, responseBody: body)
        } else if let llmError = error as? LLMKitError,
                  case .httpError(let status, let body) = llmError {
            self.init(statusCode: status, responseBody: body)
        } else {
            self.init(message: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
