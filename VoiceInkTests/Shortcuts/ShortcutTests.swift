import AppKit
import Carbon.HIToolbox
import Testing
@testable import VoiceInk

struct ShortcutTests {
    @Test func rightCommandNormalizesDeviceOnlyFlags() {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERCMDKEYMASK))

        #expect(Shortcut.normalizedModifierFlags(
            flags,
            forKeyCode: UInt16(kVK_RightCommand)
        ) == [.command])
    }

    @Test func modifierOnlyRightCommandMatchesDeviceOnlyEvent() {
        let shortcut = Shortcut.rightCommand
        let rightCommandFlags = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICERCMDKEYMASK))
        let leftCommandFlags = NSEvent.ModifierFlags(rawValue: UInt(NX_DEVICELCMDKEYMASK))

        #expect(shortcut.displayString == "Right ⌘")
        #expect(shortcut.matchesModifierEvent(
            keyCode: UInt16(kVK_RightCommand),
            modifierFlags: rightCommandFlags
        ))
        #expect(!shortcut.matchesModifierEvent(
            keyCode: UInt16(kVK_Command),
            modifierFlags: leftCommandFlags
        ))
    }

    @Test func leftAndRightCommandModifierOnlyShortcutsStayDistinct() {
        let leftCommand = Shortcut.modifierOnly(
            keyCode: UInt16(kVK_Command),
            modifierFlags: [.command]
        )
        let rightCommand = Shortcut.rightCommand

        #expect(leftCommand.displayString == "Left ⌘")
        #expect(rightCommand.displayString == "Right ⌘")
        #expect(!leftCommand.conflicts(with: rightCommand))
    }

    @Test func rightCommandEmptyFlagsCanPreviewAndFinishModifierShortcut() {
        var state = ShortcutModifierCaptureState()

        let preview = state.handleFlagsChanged(
            keyCode: UInt16(kVK_RightCommand),
            modifierFlags: []
        )

        guard case .preview(let previewShortcut) = preview else {
            Issue.record("Expected empty-flags right Command to preview a shortcut")
            return
        }

        #expect(previewShortcut.displayString == "Right ⌘")
        #expect(previewShortcut.keyCode == UInt16(kVK_RightCommand))
        #expect(previewShortcut.modifierFlags == [.command])

        let finish = state.handleFlagsChanged(
            keyCode: UInt16(kVK_RightCommand),
            modifierFlags: []
        )

        guard case .finish(let finishedShortcut) = finish else {
            Issue.record("Expected empty-flags right Command release to finish the pending shortcut")
            return
        }

        #expect(finishedShortcut == previewShortcut)
        #expect(state.pendingModifierShortcut == nil)
        #expect(state.peakModifierFlags.isEmpty)
    }

    @Test func rightCommandPartialFlagsAddMissingLogicalCommand() {
        var state = ShortcutModifierCaptureState()

        let preview = state.handleFlagsChanged(
            keyCode: UInt16(kVK_RightCommand),
            modifierFlags: [.option]
        )

        guard case .preview(let previewShortcut) = preview else {
            Issue.record("Expected partial-flags right Command to preview a shortcut")
            return
        }

        #expect(previewShortcut.modifierFlags == [.option, .command])
        #expect(previewShortcut.modifierFlags.contains(.command))
        #expect(state.pendingModifierShortcut == previewShortcut)
    }

    @Test func emptyFlagsModifierFallbackPreservesLeftRightIdentity() {
        var leftState = ShortcutModifierCaptureState()
        var rightState = ShortcutModifierCaptureState()

        let leftPreview = leftState.handleFlagsChanged(
            keyCode: UInt16(kVK_Command),
            modifierFlags: []
        )
        let rightPreview = rightState.handleFlagsChanged(
            keyCode: UInt16(kVK_RightCommand),
            modifierFlags: []
        )

        guard case .preview(let leftCommand) = leftPreview,
              case .preview(let rightCommand) = rightPreview else {
            Issue.record("Expected both command sides to preview modifier-only shortcuts")
            return
        }

        #expect(leftCommand.displayString == "Left ⌘")
        #expect(rightCommand.displayString == "Right ⌘")
        #expect(!leftCommand.conflicts(with: rightCommand))
    }

    @Test func emptyFlagsNonModifierEventDoesNotCreatePendingShortcut() {
        var state = ShortcutModifierCaptureState()

        let transition = state.handleFlagsChanged(
            keyCode: UInt16(kVK_ANSI_A),
            modifierFlags: []
        )

        #expect(transition == .none)
        #expect(state.pendingModifierShortcut == nil)
        #expect(state.peakModifierFlags.isEmpty)
    }
}
