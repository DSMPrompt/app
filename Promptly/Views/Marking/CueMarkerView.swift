//
//  CueMarkerView.swift
//  Promptly
//
//  Created by Sasha Bagrov on 04/06/2025.
//

import SwiftUI
import SwiftData

struct CueEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let line: ScriptLine
    let element: LineElement
    
    @State private var selectedCueType: CueType = .lightingGo
    @State private var cueLabel: String = ""
    @State private var cuePosition: CueOffset = .after
    @State private var hasAlert: Bool = false
    @State private var notes: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Cue Position")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Adding cue \(cuePosition.rawValue) '\(element.content)'")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Picker("Position", selection: $cuePosition) {
                            Text("Before word").tag(CueOffset.before)
                            Text("After word").tag(CueOffset.after)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
                
                Section(header: Text("Cue Type")) {
                    Picker("Type", selection: $selectedCueType) {
                        ForEach(CueType.allCases, id: \.self) { type in
                            HStack {
                                Circle()
                                    .fill(Color(hex: type.color))
                                    .frame(width: 12, height: 12)
                                Text(type.displayName)
                            }
                            .tag(type)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(WheelPickerStyle())
                    #endif
                }
                
                Section(header: Text("Cue Details")) {
                    TextField("Cue Label (e.g., LX Q5 GO)", text: $cueLabel)
                    
                    Toggle("Alert Sound", isOn: $hasAlert)
                    
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3)
                }
                
                Section(header: Text("Quick Templates")) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        QuickCueButton(type: .lightingStandby, label: "LX Q\(getNextCueNumber()) Standby") {
                            applyCueTemplate(type: .lightingStandby, label: "LX Q\(getNextCueNumber()) Standby")
                        }
                        
                        QuickCueButton(type: .lightingGo, label: "LX Q\(getNextCueNumber()) GO") {
                            applyCueTemplate(type: .lightingGo, label: "LX Q\(getNextCueNumber()) GO")
                        }
                        
                        QuickCueButton(type: .soundStandby, label: "Sound Q\(getNextSoundCue()) Standby") {
                            applyCueTemplate(type: .soundStandby, label: "Sound Q\(getNextSoundCue()) Standby")
                        }
                        
                        QuickCueButton(type: .soundGo, label: "Sound Q\(getNextSoundCue()) GO") {
                            applyCueTemplate(type: .soundGo, label: "Sound Q\(getNextSoundCue()) GO")
                        }
                    }
                }
            }
            .navigationTitle("Add Cue")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addCue()
                    }
                    .disabled(cueLabel.isEmpty)
                }
            }
        }
    }
    
    private func addCue() {
        let cue = Cue(
            id: UUID(),
            lineId: line.id,
            position: CuePosition(elementIndex: element.position, offset: cuePosition),
            type: selectedCueType,
            label: cueLabel
        )
        cue.hasAlert = hasAlert
        cue.notes = notes
        
        line.cues.append(cue)
        
        try? modelContext.save()
        dismiss()
    }
    
    private func applyCueTemplate(type: CueType, label: String) {
        selectedCueType = type
        cueLabel = label
    }
    
    private func getNextCueNumber() -> Int {
        let lightingCues = line.cues.filter { $0.type == .lightingGo || $0.type == .lightingStandby }
        return lightingCues.count + 1
    }
    
    private func getNextSoundCue() -> Int {
        let soundCues = line.cues.filter { $0.type == .soundGo || $0.type == .soundStandby }
        return soundCues.count + 1
    }
}

struct QuickCueButton: View {
    let type: CueType
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: type.color))
                    .frame(width: 20, height: 20)
                
                Text(label)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            #if os(iOS)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            #endif
            #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
            #endif
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MarkingToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let selectedLine: ScriptLine?
    let selectedElement: LineElement?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if let line = selectedLine {
                    // Line marking tools
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Mark Line \(line.lineNumber)")
                            .font(.headline)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(MarkColor.allCases, id: \.self) { color in
                                MarkColorButton(
                                    color: color,
                                    isSelected: line.markColor == color.rawValue
                                ) {
                                    toggleLineMarking(line: line, color: color)
                                }
                            }
                        }
                        
                        Button("Clear Line Marking") {
                            clearLineMarking(line: line)
                        }
                        .foregroundColor(.red)
                    }
                    .padding()
                    #if os(iOS)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    #endif
                    #if os(macOS)
                    .background(Color(nsColor: .controlBackgroundColor))
                    #endif
                    .cornerRadius(12)
                }
                
                if let element = selectedElement {
                    // Word marking tools
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Mark Word '\(element.content)'")
                            .font(.headline)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(MarkColor.allCases, id: \.self) { color in
                                MarkColorButton(
                                    color: color,
                                    isSelected: element.markColor == color.rawValue
                                ) {
                                    toggleElementMarking(element: element, color: color)
                                }
                            }
                        }
                        
                        Button("Clear Word Marking") {
                            clearElementMarking(element: element)
                        }
                        .foregroundColor(.red)
                    }
                    .padding()
                    #if os(iOS)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    #endif
                    #if os(macOS)
                    .background(Color(nsColor: .controlBackgroundColor))
                    #endif
                    .cornerRadius(12)
                }
                
                if selectedLine == nil && selectedElement == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.tap")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        
                        Text("Select a line or word to mark")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Marking Tools")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func toggleLineMarking(line: ScriptLine, color: MarkColor) {
        if line.markColor == color.rawValue {
            // Already this color, remove marking
            line.isMarked = false
            line.markColor = nil
        } else {
            // Apply new color
            line.isMarked = true
            line.markColor = color.rawValue
        }
        try? modelContext.save()
    }
    
    private func clearLineMarking(line: ScriptLine) {
        line.isMarked = false
        line.markColor = nil
        try? modelContext.save()
    }
    
    private func toggleElementMarking(element: LineElement, color: MarkColor) {
        if element.markColor == color.rawValue {
            // Already this color, remove marking
            element.isMarked = false
            element.markColor = nil
        } else {
            // Apply new color
            element.isMarked = true
            element.markColor = color.rawValue
        }
        try? modelContext.save()
    }
    
    private func clearElementMarking(element: LineElement) {
        element.isMarked = false
        element.markColor = nil
        try? modelContext.save()
    }
}

struct MarkColorButton: View {
    let color: MarkColor
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: color.rawValue))
                    .frame(height: 30)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.primary : Color.clear, lineWidth: 2)
                    )
                
                Text(color.displayName)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
