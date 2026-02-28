//
//  InlineCueEntryView.swift
//  Promptly
//
//
//

import SwiftUI
import SwiftData

struct InlineCueEntryView: View {
	let line: ScriptLine
	let selectedWord: LineElement
	@Binding var isPresented: Bool
	let state: InlineCueEntryState
	let onSave: (Cue) -> Void

	@FocusState private var focusedField: FocusField?

	enum FocusField: Hashable {
		case cueNumber
		case description
	}

	private var cueTypeGrid: some View {
		LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 8) {
			CueTypeButton(type: .lightingGo, shortcut: "L", selected: state.selectedCueType == .lightingGo) {
				state.selectedCueType = .lightingGo
				state.cueNumber = state.nextCueNumber(for: .lightingGo, in: line)
			}
			CueTypeButton(type: .lightingStandby, shortcut: "⇧L", selected: state.selectedCueType == .lightingStandby) {
				state.selectedCueType = .lightingStandby
				state.cueNumber = state.nextCueNumber(for: .lightingStandby, in: line)
			}
			CueTypeButton(type: .soundGo, shortcut: "S", selected: state.selectedCueType == .soundGo) {
				state.selectedCueType = .soundGo
				state.cueNumber = state.nextCueNumber(for: .soundGo, in: line)
			}
			CueTypeButton(type: .soundStandby, shortcut: "⇧S", selected: state.selectedCueType == .soundStandby) {
				state.selectedCueType = .soundStandby
				state.cueNumber = state.nextCueNumber(for: .soundStandby, in: line)
			}
			CueTypeButton(type: .flyGo, shortcut: "F", selected: state.selectedCueType == .flyGo) {
				state.selectedCueType = .flyGo
				state.cueNumber = state.nextCueNumber(for: .flyGo, in: line)
			}
			CueTypeButton(type: .flyStandby, shortcut: "⇧F", selected: state.selectedCueType == .flyStandby) {
				state.selectedCueType = .flyStandby
				state.cueNumber = state.nextCueNumber(for: .flyStandby, in: line)
			}
			CueTypeButton(type: .automationGo, shortcut: "A", selected: state.selectedCueType == .automationGo) {
				state.selectedCueType = .automationGo
				state.cueNumber = state.nextCueNumber(for: .automationGo, in: line)
			}
			CueTypeButton(type: .automationStandby, shortcut: "⇧A", selected: state.selectedCueType == .automationStandby) {
				state.selectedCueType = .automationStandby
				state.cueNumber = state.nextCueNumber(for: .automationStandby, in: line)
			}
			CueTypeButton(type: .cuelightGo, shortcut: "C", selected: state.selectedCueType == .cuelightGo) {
				state.selectedCueType = .cuelightGo
				state.cueNumber = state.nextCueNumber(for: .cuelightGo, in: line)
			}
			CueTypeButton(type: .cuelightStandby, shortcut: "⇧C", selected: state.selectedCueType == .cuelightStandby) {
				state.selectedCueType = .cuelightStandby
				state.cueNumber = state.nextCueNumber(for: .cuelightStandby, in: line)
			}
			CueTypeButton(type: .setGo, shortcut: "T", selected: state.selectedCueType == .setGo) {
				state.selectedCueType = .setGo
				state.cueNumber = state.nextCueNumber(for: .setGo, in: line)
			}
			CueTypeButton(type: .setStandby, shortcut: "⇧T", selected: state.selectedCueType == .setStandby) {
				state.selectedCueType = .setStandby
				state.cueNumber = state.nextCueNumber(for: .setStandby, in: line)
			}
		}
	}

	var body: some View {
		@Bindable var state = state

		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Text("Add Cue at: \"\(selectedWord.content)\"")
					.font(.headline)
					.foregroundStyle(.primary)

				Spacer()

				Button(action: { isPresented = false }) {
					Image(systemName: "xmark.circle.fill")
						.foregroundStyle(.secondary)
				}
				.buttonStyle(.plain)
			}

			Divider()

			VStack(alignment: .leading, spacing: 6) {
				HStack {
					Text("Position")
						.font(.subheadline)
						.foregroundStyle(.secondary)
					Text("(Space to toggle)")
						.font(.caption)
						.foregroundStyle(.tertiary)
				}

				HStack(spacing: 0) {
					ForEach(CueOffset.allCases, id: \.self) { offset in
						Button(action: { state.selectedOffset = offset }) {
							Text(offset == .before ? "Before word" : "After word")
								.font(.subheadline)
								.frame(maxWidth: .infinity)
								.padding(.vertical, 6)
								.background(state.selectedOffset == offset ? Color.accentColor : Color.clear)
								.foregroundStyle(state.selectedOffset == offset ? Color.white : Color.primary)
						}
						.buttonStyle(.plain)
					}
				}
				.background(Color.gray.opacity(0.15))
				.clipShape(RoundedRectangle(cornerRadius: 8))
			}

			VStack(alignment: .leading, spacing: 8) {
				Text("Cue Type")
					.font(.subheadline)
					.foregroundStyle(.secondary)

				cueTypeGrid
			}

			VStack(alignment: .leading, spacing: 4) {
				HStack {
					Text("Cue Number")
						.font(.subheadline)
						.foregroundStyle(.secondary)
					Text("(Tab to edit)")
						.font(.caption)
						.foregroundStyle(.tertiary)
				}

				TextField("Auto", text: $state.cueNumber)
					.textFieldStyle(.roundedBorder)
					.focused($focusedField, equals: .cueNumber)
					.onSubmit { isPresented = false }
			}

			VStack(alignment: .leading, spacing: 4) {
				Text("Description (Optional)")
					.font(.subheadline)
					.foregroundStyle(.secondary)

				TextField("Brief description", text: $state.cueDescription)
					.textFieldStyle(.roundedBorder)
					.focused($focusedField, equals: .description)
					.onSubmit { isPresented = false }
			}

			Divider()

			VStack(alignment: .leading, spacing: 2) {
				Text("↵ Save  •  ⎋ Cancel  •  Space: toggle position")
					.font(.caption)
					.foregroundStyle(.secondary)
				Text("← → navigate words  •  ↑ ↓ navigate lines  •  L/S/F/A/C/T: cue type  •  ⇧ for standby")
					.font(.caption)
					.foregroundStyle(.tertiary)
			}
		}
	}
}

// MARK: - Cue Type Button

struct CueTypeButton: View {
	let type: CueType
	let shortcut: String
	let selected: Bool
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text(type.displayName)
						.font(.subheadline)
						.fontWeight(selected ? .semibold : .regular)

					Text(shortcut)
						.font(.caption2)
						.foregroundStyle(.secondary)
				}

				Spacer()

				if selected {
					Image(systemName: "checkmark.circle.fill")
						.foregroundStyle(Color(hex: type.color))
				}
			}
			.padding(.horizontal, 10)
			.padding(.vertical, 8)
			.frame(maxWidth: .infinity)
			.background(
				RoundedRectangle(cornerRadius: 6)
					.fill(selected ? Color(hex: type.color).opacity(0.2) : Color.gray.opacity(0.1))
			)
			.overlay(
				RoundedRectangle(cornerRadius: 6)
					.stroke(selected ? Color(hex: type.color) : Color.clear, lineWidth: 2)
			)
		}
		.buttonStyle(.plain)
	}
}
