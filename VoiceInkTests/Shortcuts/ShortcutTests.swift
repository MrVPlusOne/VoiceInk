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
}
