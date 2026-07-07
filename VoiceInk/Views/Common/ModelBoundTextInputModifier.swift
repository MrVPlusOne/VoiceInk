import AppKit
import SwiftUI

extension View {
    func modelBoundTextInput() -> some View {
        self
            .autocorrectionDisabled(true)
            .background(ModelBoundTextInputConfigurator())
    }
}

private struct ModelBoundTextInputConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        scheduleConfiguration(from: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        scheduleConfiguration(from: nsView)
    }

    private func scheduleConfiguration(from view: NSView, attempt: Int = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(attempt == 0 ? 0 : 25)) {
            guard let textView = findTextView(near: view) else {
                if attempt < 8 {
                    scheduleConfiguration(from: view, attempt: attempt + 1)
                }
                return
            }
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false
            textView.isAutomaticSpellingCorrectionEnabled = false
            textView.isContinuousSpellCheckingEnabled = false
            textView.isGrammarCheckingEnabled = false
        }
    }

    private func findTextView(near view: NSView) -> NSTextView? {
        var current: NSView? = view
        while let candidate = current {
            if let textView = firstTextView(in: candidate) {
                return textView
            }
            current = candidate.superview
        }
        return nil
    }

    private func firstTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = firstTextView(in: subview) {
                return textView
            }
        }

        return nil
    }
}
