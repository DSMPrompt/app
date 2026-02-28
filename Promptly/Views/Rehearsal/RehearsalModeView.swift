//
//  RehearsalModeView.swift
//  Promptly
//
//	Created by Sasha Bagrov at 27/02/2026
//

import SwiftUI
import SwiftData

struct RehearsalModeView: View {
	@Environment(\.modelContext) private var modelContext
	let script: Script

	@State private var currentLineIndex: Int = 0
	@State private var selectedWordIndex: Int = 0
	@State private var isInlineMode: Bool = false
	@State private var scrollProxy: ScrollViewProxy?
	@State private var sortedLines: [ScriptLine] = []
	@State private var inlineState = InlineCueEntryState()
	@FocusState private var isFocused: Bool

	private var currentLine: ScriptLine? {
		guard currentLineIndex < sortedLines.count else { return nil }
		return sortedLines[currentLineIndex]
	}

	private var currentLineWords: [LineElement] {
		currentLine?.elements
			.filter { $0.type == .word }
			.sorted { $0.position < $1.position } ?? []
	}

	private var selectedWord: LineElement? {
		guard selectedWordIndex < currentLineWords.count else { return nil }
		return currentLineWords[selectedWordIndex]
	}

	var body: some View {
		HStack(alignment: .top, spacing: 0) {
			ScrollViewReader { proxy in
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 12) {
						ForEach(Array(sortedLines.enumerated()), id: \.element.id) { index, line in
							RehearsalLineView(
								line: line,
								isCurrentLine: index == currentLineIndex,
								selectedWordIndex: isInlineMode && index == currentLineIndex ? selectedWordIndex : nil
							)
							.id(line.id)
							.contentShape(Rectangle())
							.onTapGesture {
								selectLine(at: index)
							}
						}
					}
					.padding()
				}
				.onAppear {
					scrollProxy = proxy
					sortedLines = script.lines.sorted { $0.lineNumber < $1.lineNumber }
					isFocused = true
				}
				.onChange(of: script.lines.count) {
					sortedLines = script.lines.sorted { $0.lineNumber < $1.lineNumber }
				}
			}

			if isInlineMode, let word = selectedWord, let line = currentLine {
				Divider()

				ScrollView {
					InlineCueEntryView(
						line: line,
						selectedWord: word,
						isPresented: $isInlineMode,
						state: inlineState,
						onSave: { cue in saveCue(cue) }
					)
					.padding()
				}
				.frame(width: 380)
				.transition(.move(edge: .trailing))
			}
		}
		.animation(.easeInOut(duration: 0.2), value: isInlineMode)
		.focusable()
		.focused($isFocused)
		.navigationTitle("Rehearsal Mode - \(script.name)")
		.onKeyPress { keyPress in
			if isInlineMode {
				return inlineState.handleKeyPress(
					keyPress,
					dismiss: {
						isInlineMode = false
						isFocused = true
					},
					save: { commitInlineCue() },
					previousWord: {
						if selectedWordIndex > 0 { selectedWordIndex -= 1 }
					},
					nextWord: {
						if selectedWordIndex < currentLineWords.count - 1 { selectedWordIndex += 1 }
					},
					previousLine: {
						if currentLineIndex > 0 {
							currentLineIndex -= 1
							selectedWordIndex = 0
							scrollToCurrentLine()
						}
					},
					nextLine: {
						if currentLineIndex < sortedLines.count - 1 {
							currentLineIndex += 1
							selectedWordIndex = 0
							scrollToCurrentLine()
						}
					},
					refreshCueNumber: {
						guard let line = currentLine else { return }
						inlineState.cueNumber = inlineState.nextCueNumber(for: inlineState.selectedCueType, in: line)
					}
				)
			}

			switch keyPress.key {
			case .space, .downArrow:
				if currentLineIndex < sortedLines.count - 1 {
					currentLineIndex += 1
					selectedWordIndex = 0
					scrollToCurrentLine()
				}
				return .handled
			case .upArrow:
				if currentLineIndex > 0 {
					currentLineIndex -= 1
					selectedWordIndex = 0
					scrollToCurrentLine()
				}
				return .handled
			case .leftArrow:
				if selectedWordIndex > 0 { selectedWordIndex -= 1 }
				return .handled
			case .rightArrow:
				if selectedWordIndex < currentLineWords.count - 1 { selectedWordIndex += 1 }
				return .handled
			default:
				return .ignored
			}
		}
		.background {
			Button("") { activateInlineMode() }
				.keyboardShortcut("k", modifiers: .command)
				.hidden()
		}
	}

	private func selectLine(at index: Int) {
		currentLineIndex = index
		scrollToCurrentLine()
	}

	private func scrollToCurrentLine() {
		guard let line = currentLine else { return }
		withAnimation {
			scrollProxy?.scrollTo(line.id, anchor: .center)
		}
	}

	private func activateInlineMode() {
		guard let line = currentLine, !currentLineWords.isEmpty else { return }
		selectedWordIndex = 0
		inlineState.selectedCueType = .lightingGo
		inlineState.selectedOffset = .after
		inlineState.cueDescription = ""
		inlineState.cueNumber = inlineState.nextCueNumber(for: .lightingGo, in: line)
		isInlineMode = true
	}

	private func commitInlineCue() {
		guard let line = currentLine, let word = selectedWord else { return }
		let finalNumber = inlineState.cueNumber.isEmpty
			? inlineState.nextCueNumber(for: inlineState.selectedCueType, in: line)
			: inlineState.cueNumber
		let label = buildCueLabel(type: inlineState.selectedCueType, number: finalNumber)
		let cue = Cue(
			id: UUID(),
			lineId: line.id,
			position: CuePosition(elementIndex: word.position, offset: inlineState.selectedOffset),
			type: inlineState.selectedCueType,
			label: label
		)
		if !inlineState.cueDescription.isEmpty { cue.notes = inlineState.cueDescription }
		saveCue(cue)
		inlineState.reset(for: inlineState.selectedCueType, in: line)
	}

	private func saveCue(_ cue: Cue) {
		guard let line = currentLine else { return }
		line.cues.append(cue)
		do {
			try modelContext.save()
		} catch {
			print("Error saving cue: \(error)")
		}
	}

	private func buildCueLabel(type: CueType, number: String) -> String {
		switch type {
		case .lightingGo:        return "LX Q\(number) GO"
		case .lightingStandby:   return "LX Q\(number) Standby"
		case .soundGo:           return "SFX Q\(number) GO"
		case .soundStandby:      return "SFX Q\(number) Standby"
		case .flyGo:             return "Fly Q\(number) GO"
		case .flyStandby:        return "Fly Q\(number) Standby"
		case .automationGo:      return "Auto Q\(number) GO"
		case .automationStandby: return "Auto Q\(number) Standby"
		case .setGo:             return "Set Q\(number) GO"
		case .setStandby:        return "Set Q\(number) Standby"
		case .cuelightGo:        return "Cuelight Q\(number) GO"
		case .cuelightStandby:   return "Cuelight Q\(number) Standby"
		}
	}
}

// MARK: - Flow Layout

struct FlowLayoutRV: Layout {
	var spacing: CGFloat = 4

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let rows = computeRows(proposal: proposal, subviews: subviews)
		let height = rows.map { row in
			row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
		}.reduce(0) { $0 + $1 + spacing }
		return CGSize(width: proposal.width ?? 0, height: max(0, height - spacing))
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		let rows = computeRows(proposal: proposal, subviews: subviews)
		var y = bounds.minY
		for row in rows {
			let rowHeight = row.map { subviews[$0].sizeThatFits(.unspecified).height }.max() ?? 0
			var x = bounds.minX
			for index in row {
				let size = subviews[index].sizeThatFits(.unspecified)
				subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
				x += size.width + spacing
			}
			y += rowHeight + spacing
		}
	}

	private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[Int]] {
		let maxWidth = proposal.width ?? .infinity
		var rows: [[Int]] = [[]]
		var x: CGFloat = 0
		for (i, subview) in subviews.enumerated() {
			let size = subview.sizeThatFits(.unspecified)
			if x + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
				rows.append([])
				x = 0
			}
			rows[rows.count - 1].append(i)
			x += size.width + spacing
		}
		return rows
	}
}

// MARK: - Rehearsal Line View

struct RehearsalLineView: View {
	let line: ScriptLine
	let isCurrentLine: Bool
	let selectedWordIndex: Int?

	private var words: [LineElement] {
		line.elements
			.filter { $0.type == .word }
			.sorted { $0.position < $1.position }
	}

	private func cues(at wordPosition: Int, offset: CueOffset) -> [Cue] {
		line.cues
			.filter { $0.position.elementIndex == wordPosition && $0.position.offset == offset }
			.sorted { $0.label < $1.label }
	}

	var body: some View {
		HStack(alignment: .top, spacing: 8) {
			Text("\(line.lineNumber)")
				.font(.system(.caption, design: .monospaced))
				.foregroundStyle(.secondary)
				.frame(width: 40, alignment: .trailing)
				.padding(.top, 4)

			FlowLayoutRV(spacing: 4) {
				ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
					ForEach(cues(at: word.position, offset: .before)) { cue in
						CueIndicatorChip(cue: cue)
					}

					Text(word.content)
						.font(.body)
						.padding(.horizontal, 4)
						.padding(.vertical, 2)
						.background(
							Group {
								if selectedWordIndex == index && isCurrentLine {
									RoundedRectangle(cornerRadius: 4)
										.fill(Color.accentColor.opacity(0.3))
								} else {
									Color.clear
								}
							}
						)

					ForEach(cues(at: word.position, offset: .after)) { cue in
						CueIndicatorChip(cue: cue)
					}
				}
			}
		}
		.padding(.vertical, 8)
		.padding(.horizontal, 12)
		.background(
			RoundedRectangle(cornerRadius: 8)
				.fill(isCurrentLine ? Color.accentColor.opacity(0.1) : Color.clear)
		)
	}
}

// MARK: - Cue Indicator Chip

struct CueIndicatorChip: View {
	let cue: Cue

	var body: some View {
		Text(cue.label)
			.font(.system(.caption2, design: .monospaced))
			.padding(.horizontal, 6)
			.padding(.vertical, 2)
			.background(
				RoundedRectangle(cornerRadius: 4)
					.fill(Color(hex: cue.type.color).opacity(0.3))
			)
			.foregroundStyle(Color(hex: cue.type.color))
	}
}
