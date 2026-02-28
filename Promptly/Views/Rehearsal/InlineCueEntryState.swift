//
//  InlineCueEntryState.swift
//  Promptly
//
//  Created by Sasha Bagrov on 28/02/2026.
//

import SwiftUI

@Observable
class InlineCueEntryState {
	var selectedCueType: CueType = .lightingGo
	var cueNumber: String = ""
	var cueDescription: String = ""
	var selectedOffset: CueOffset = .after

	func nextCueNumber(for type: CueType, in line: ScriptLine) -> String {
		let numbers = line.cues.filter { $0.type == type }.compactMap { cue -> Int? in
			let parts = cue.label.split(separator: " ")
			guard parts.count > 1 else { return nil }
			return Int(parts[1].replacingOccurrences(of: "Q", with: ""))
		}
		return String((numbers.max() ?? 0) + 1)
	}

	func reset(for type: CueType, in line: ScriptLine) {
		cueDescription = ""
		cueNumber = nextCueNumber(for: type, in: line)
	}

	func handleKeyPress(
		_ keyPress: KeyPress,
		dismiss: () -> Void,
		save: () -> Void,
		previousWord: () -> Void,
		nextWord: () -> Void,
		previousLine: () -> Void,
		nextLine: () -> Void,
		refreshCueNumber: () -> Void
	) -> KeyPress.Result {
		let isShift = keyPress.modifiers.contains(.shift)

		switch keyPress.key {
		case .escape:
			dismiss()
			return .handled
		case .return:
			save()
			return .handled
		case KeyEquivalent(" "):
			selectedOffset = selectedOffset == .before ? .after : .before
			return .handled
		case .leftArrow:
			previousWord()
			return .handled
		case .rightArrow:
			nextWord()
			return .handled
		case .upArrow:
			previousLine()
			return .handled
		case .downArrow:
			nextLine()
			return .handled
		default:
			break
		}

		switch (keyPress.characters.lowercased(), isShift) {
		case ("l", false): selectedCueType = .lightingGo
		case ("l", true):  selectedCueType = .lightingStandby
		case ("s", false): selectedCueType = .soundGo
		case ("s", true):  selectedCueType = .soundStandby
		case ("f", false): selectedCueType = .flyGo
		case ("f", true):  selectedCueType = .flyStandby
		case ("a", false): selectedCueType = .automationGo
		case ("a", true):  selectedCueType = .automationStandby
		case ("c", false): selectedCueType = .cuelightGo
		case ("c", true):  selectedCueType = .cuelightStandby
		case ("t", false): selectedCueType = .setGo
		case ("t", true):  selectedCueType = .setStandby
		default:           return .ignored
		}
		refreshCueNumber()
		return .handled
	}
}
