//
//  EditScriptView.swift
//  Promptly
//
//  Created by Sasha Bagrov on 04/06/2025.
//

import SwiftUI
import SwiftData

class RefreshTrigger: ObservableObject {
    func refresh() {
        objectWillChange.send()
    }
}

struct EditScriptView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let script: Script
    @State private var isEditing = false
    @State private var selectedLines: Set<UUID> = []
    @State private var showingDeleteAlert = false
    @State private var showingCueWarning = false
    @State private var linesToDelete: [ScriptLine] = []
    @State private var editingLineId: UUID?
    @State private var editingText = ""
    @State private var newLineText = ""
    @State private var insertAfterLineNumber: Int?
    @State private var showingAddLine = false
    @State private var showingCombineConfirm = false
    @State private var showingAddSection = false
    @State private var showingSections = false
    @State private var isSelectingLineForSection = false
    @State private var pendingSectionType: SectionType = .scene
    @State private var pendingSectionTitle = ""
    @State private var pendingSectionNotes = ""
    @State private var showingLineConfirmation = false
    @State private var selectedLineForSection: ScriptLine?
    @State private var showingFlagEditor = false
    @State private var lineBeingFlagged: ScriptLine?
    @StateObject private var refreshTrigger = RefreshTrigger()
    
    var sortedLines: [ScriptLine] {
        script.lines.sorted { $0.lineNumber < $1.lineNumber }
    }
    
    var sortedSections: [ScriptSection] {
        script.sections.sorted { $0.startLineNumber < $1.startLineNumber }
    }
    
    var selectedLinesArray: [ScriptLine] {
        selectedLines.compactMap { id in
            sortedLines.first { $0.id == id }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isSelectingLineForSection {
                selectionOverlay
            }
            
            mainContentView
        }
        .alert("Combine Lines", isPresented: .constant(false)) {
            Button("Cancel", role: .cancel) { }
            Button("Combine") { }
        } message: {
            Text("This will merge lines into one. Cues from all lines will be preserved. This action cannot be undone.")
        }
        .alert("Combine Lines", isPresented: $showingCombineConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Combine") {
                combineSelectedLines()
            }
        } message: {
            Text("This will merge \(selectedLines.count) lines into one. Cues from all lines will be preserved. This action cannot be undone.")
        }
        .alert("Delete Lines with Cues", isPresented: $showingCueWarning) {
            Button("Cancel", role: .cancel) {
                linesToDelete.removeAll()
            }
            Button("Delete Anyway", role: .destructive) {
                deleteSelectedLines()
            }
        } message: {
            Text("Some selected lines contain cues that will be permanently deleted. This action cannot be undone.")
        }
        .alert("Delete Lines", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                linesToDelete.removeAll()
            }
            Button("Delete", role: .destructive) {
                deleteSelectedLines()
            }
        } message: {
            Text("Are you sure you want to delete \(selectedLines.count) line(s)? This action cannot be undone.")
        }
        .alert("Confirm Section Start", isPresented: $showingLineConfirmation) {
            Button("Cancel", role: .cancel) {
                selectedLineForSection = nil
                isSelectingLineForSection = true
            }
            Button("Confirm") {
                createSectionWithSelectedLine()
            }
        } message: {
            if let line = selectedLineForSection {
                Text("Start '\(pendingSectionTitle)' at line \(line.lineNumber)?\n\n\"\(line.content.prefix(100))...\"")
            }
        }
        .sheet(isPresented: $showingAddLine) {
            AddLineView(
                insertAfterLineNumber: insertAfterLineNumber,
                script: script
            ) {
                renumberLines()
            }
        }
        .sheet(isPresented: $showingFlagEditor) {
            if selectedLines.count == 1, let line = selectedLinesArray.first {
                FlagEditorView(line: line) {
                    try? modelContext.save()
                    refreshTrigger.refresh()
                }
            } else if selectedLines.count > 1 {
                BulkFlagEditorView(lines: selectedLinesArray) {
                    try? modelContext.save()
                    refreshTrigger.refresh()
                }
            }
        }
        .sheet(isPresented: $showingAddSection) {
            SectionDetailsView(
                pendingTitle: $pendingSectionTitle,
                pendingType: $pendingSectionType,
                pendingNotes: $pendingSectionNotes
            ) { title, type, notes in
                pendingSectionTitle = title
                pendingSectionType = type
                pendingSectionNotes = notes
                isSelectingLineForSection = true
            }
        }
        .sheet(isPresented: $showingSections) {
            SectionsManagerView(
                script: script,
                calledFromEditView: true
            ) { title, type, notes in
                // Handle the section creation request from SectionsManagerView
                pendingSectionTitle = title
                pendingSectionType = type
                pendingSectionNotes = notes
                isSelectingLineForSection = true
            }
        }
        .toolbar {
            ToolbarItem(content: {
                if isEditing {
                    Button {
                        cancelEditing()
                    } label: {
                        Image(systemName: "pencil.slash")
                    }
                }
                
                Menu {
                    if isEditing {
                        Button("Save", systemImage: "checkmark") {
                            saveChanges()
                        }
                    } else {
                        Button("Edit Script", systemImage: "pencil") {
                            isEditing = true
                        }
                    }
                    
                    Divider()
                    
                    Button("Sections", systemImage: "list.bullet.rectangle") {
                        showingSections = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            })
        }
        .navigationTitle(Text(script.name))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    
    // MARK: - View Components
    
    private var selectionOverlay: some View {
        VStack(spacing: 12) {
            Text("Select Start Line for Section")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Tap a line to mark where '\(pendingSectionTitle)' begins")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
            
            Button("Cancel") {
                isSelectingLineForSection = false
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.2))
            .cornerRadius(8)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.blue.opacity(0.9))
    }
    
    private var mainContentView: some View {
        VStack(spacing: 0) {
            if isEditing {
                editControlsView
            }
            
            scriptContentView
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue, lineWidth: isSelectingLineForSection ? 4 : 0)
                .animation(.easeInOut(duration: 0.2), value: isSelectingLineForSection)
        )
    }
    
    private var editControlsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button("Select All") {
                    selectedLines = Set(sortedLines.map { $0.id })
                }
                
                if !selectedLines.isEmpty {
                    Text("\(selectedLines.count) selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                    
                    if selectedLines.count > 1 {
                        Button("Combine Lines") {
                            showingCombineConfirm = true
                        }
                        .foregroundColor(.blue)
                    }
                    
                    Button("Edit Flags") {
                        // For single line, set the line. For multiple, set to nil for bulk mode
                        if selectedLines.count == 1,
                           let lineId = selectedLines.first,
                           let line = sortedLines.first(where: { $0.id == lineId }) {
                            lineBeingFlagged = line
                        } else {
                            lineBeingFlagged = nil // Bulk mode
                        }
                        showingFlagEditor = true
                    }
                    .foregroundColor(.purple)
                    
                    Button("Delete") {
                        confirmDelete()
                    }
                    .foregroundColor(.red)
                }
                
                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        #if os(iOS)
        .background(Color(uiColor: .systemGroupedBackground))
        #endif
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
    }
    
    private var scriptContentView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(sortedLines, id: \.id) { line in
                    EditableScriptLineView(
                        line: line,
                        isEditing: isEditing,
                        isSelected: selectedLines.contains(line.id),
                        isEditingText: editingLineId == line.id,
                        isSelectingForSection: isSelectingLineForSection,
                        editingText: $editingText
                    ) { selectedLine in
                        if isSelectingLineForSection {
                            selectedLineForSection = selectedLine
                            showingLineConfirmation = true
                            isSelectingLineForSection = false
                        } else {
                            toggleLineSelection(selectedLine)
                        }
                    } onStartTextEdit: { lineToEdit in
                        startEditing(line: lineToEdit)
                    } onFinishTextEdit: { newText in
                        finishEditing(newText: newText)
                    } onInsertAfter: { lineToInsertAfter in
                        insertAfterLineNumber = lineToInsertAfter.lineNumber
                        showingAddLine = true
                    } onEditFlags: { lineToFlag in
                        lineBeingFlagged = lineToFlag
                        showingFlagEditor = true
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Actions
    
    private func toggleLineSelection(_ line: ScriptLine) {
        if selectedLines.contains(line.id) {
            selectedLines.remove(line.id)
        } else {
            selectedLines.insert(line.id)
        }
    }
    
    private func startEditing(line: ScriptLine) {
        editingLineId = line.id
        editingText = line.content
    }
    
    private func finishEditing(newText: String) {
        if let lineId = editingLineId,
           let line = script.lines.first(where: { $0.id == lineId }) {
            line.content = newText
            line.parseContentIntoElements()
            try? modelContext.save()
        }
        editingLineId = nil
        editingText = ""
    }
    
    private func confirmDelete() {
        linesToDelete = selectedLines.compactMap { id in
            script.lines.first { $0.id == id }
        }
        
        let hasLinesWithCues = linesToDelete.contains { !$0.cues.isEmpty }
        
        if hasLinesWithCues {
            showingCueWarning = true
        } else {
            showingDeleteAlert = true
        }
    }
    
    private func deleteSelectedLines() {
        let linesToRemove = selectedLines.compactMap { id in
            script.lines.first { $0.id == id }
        }
        
        for line in linesToRemove {
            script.lines.removeAll { $0.id == line.id }
            modelContext.delete(line)
        }
        
        selectedLines.removeAll()
        linesToDelete.removeAll()
        renumberLines()
        try? modelContext.save()
    }
    
    private func combineSelectedLines() {
        let linesToCombine = selectedLines.compactMap { id in
            script.lines.first { $0.id == id }
        }.sorted { $0.lineNumber < $1.lineNumber }
        
        guard let firstLine = linesToCombine.first else { return }
        
        let combinedContent = linesToCombine.map { $0.content }.joined(separator: " ")
        let allCues = linesToCombine.flatMap { $0.cues }
        let allFlags = Array(Set(linesToCombine.flatMap { $0.flags }))
        
        firstLine.content = combinedContent
        firstLine.flags = allFlags
        firstLine.parseContentIntoElements()
        
        for cue in allCues {
            cue.lineId = firstLine.id
        }
        
        let linesToRemove = Array(linesToCombine.dropFirst())
        for line in linesToRemove {
            script.lines.removeAll { $0.id == line.id }
            modelContext.delete(line)
        }
        
        selectedLines.removeAll()
        renumberLines()
        try? modelContext.save()
    }
    
    private func createSectionWithSelectedLine() {
        guard let selectedLine = selectedLineForSection else { return }
        
        let newSection = ScriptSection(
            id: UUID(),
            title: pendingSectionTitle,
            type: pendingSectionType,
            startLineNumber: selectedLine.lineNumber
        )
        
        script.sections.append(newSection)
        
        selectedLineForSection = nil
        isSelectingLineForSection = false
        pendingSectionTitle = ""
        pendingSectionNotes = ""
        
        try? modelContext.save()
    }
    
    private func renumberLines() {
        let sortedLines = script.lines.sorted { $0.lineNumber < $1.lineNumber }
        for (index, line) in sortedLines.enumerated() {
            line.lineNumber = index + 1
        }
        try? modelContext.save()
    }
    
    private func saveChanges() {
        try? modelContext.save()
        isEditing = false
        selectedLines.removeAll()
    }
    
    private func cancelEditing() {
        isEditing = false
        selectedLines.removeAll()
        editingLineId = nil
        editingText = ""
    }
}

struct EditableScriptLineView: View {
    let line: ScriptLine
    let isEditing: Bool
    let isSelected: Bool
    let isEditingText: Bool
    let isSelectingForSection: Bool
    @Binding var editingText: String
    
    let onToggleSelection: (ScriptLine) -> Void
    let onStartTextEdit: (ScriptLine) -> Void
    let onFinishTextEdit: (String) -> Void
    let onInsertAfter: (ScriptLine) -> Void
    let onEditFlags: (ScriptLine) -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 8) {
                if isEditing {
                    Button(action: { onToggleSelection(line) }) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isSelected ? .blue : .gray)
                    }
                }
                
                Text("\(line.lineNumber)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .trailing)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if isEditingText {
                    TextField("Line content", text: $editingText, onCommit: {
                        onFinishTextEdit(editingText)
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                } else {
                    Button(action: {
                        if isSelectingForSection {
                            onToggleSelection(line)
                        } else if isEditing {
                            onStartTextEdit(line)
                        }
                    }) {
                        Text(line.content)
                            .font(.body)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(!(isEditing || isSelectingForSection))
                }
                
                // Flag indicators
                if !line.flags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(line.flags, id: \.self) { flag in
                            flagBadge(for: flag)
                        }
                    }
                }
                
                if !line.cues.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        
                        Text("\(line.cues.count) cue(s)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            if isEditing && isSelected {
                VStack(spacing: 4) {
                    Button(action: { onEditFlags(line) }) {
                        Image(systemName: "flag")
                            .foregroundColor(.purple)
                    }
                    
                    Button(action: { onInsertAfter(line) }) {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.blue)
                    }
                }
                .font(.title3)
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColorForLine)
                .opacity(backgroundOpacity)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: borderWidth)
        )
    }
    
    private func flagBadge(for flag: ScriptLineFlags) -> some View {
        HStack(spacing: 2) {
            Image(systemName: iconForFlag(flag))
                .font(.caption2)
            Text(labelForFlag(flag))
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(colorForFlag(flag))
        .foregroundColor(.white)
        .cornerRadius(4)
    }
    
    private func iconForFlag(_ flag: ScriptLineFlags) -> String {
        switch flag {
        case .stageDirection:
            return "theatermasks"
        case .skip:
            return "forward.fill"
        }
    }
    
    private func labelForFlag(_ flag: ScriptLineFlags) -> String {
        switch flag {
        case .stageDirection:
            return "Stage"
        case .skip:
            return "Skip"
        }
    }
    
    private func colorForFlag(_ flag: ScriptLineFlags) -> Color {
        switch flag {
        case .stageDirection:
            return .purple
        case .skip:
            return .red
        }
    }
    
    private var backgroundColorForLine: Color {
        if line.isMarked, let colorHex = line.markColor {
            return Color(hex: colorHex)
        }
        #if os(iOS)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #endif
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #endif
    }
    
    private var backgroundOpacity: Double {
        if isSelected && isEditing {
            return 0.6
        } else if line.isMarked {
            return 0.3
        } else {
            return 0.1
        }
    }
    
    private var borderColor: Color {
        if isSelected && isEditing {
            return .blue
        } else if !line.cues.isEmpty {
            return .orange
        } else {
            return .clear
        }
    }
    
    private var borderWidth: CGFloat {
        (isSelected && isEditing) || !line.cues.isEmpty ? 1 : 0
    }
}

struct FlagEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let line: ScriptLine
    let onSave: () -> Void
    
    @State private var selectedFlags: Set<ScriptLineFlags> = []
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Line \(line.lineNumber)")) {
                    Text(line.content)
                        .font(.body)
                        .foregroundColor(.primary)
                }
                
                Section(header: Text("Flags")) {
                    ForEach(ScriptLineFlags.allCases, id: \.self) { flag in
                        HStack {
                            Button(action: {
                                toggleFlag(flag)
                            }) {
                                HStack {
                                    Image(systemName: selectedFlags.contains(flag) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedFlags.contains(flag) ? .blue : .gray)
                                    
                                    HStack(spacing: 8) {
                                        Image(systemName: iconForFlag(flag))
                                            .foregroundColor(colorForFlag(flag))
                                        Text(labelForFlag(flag))
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        Text(descriptionForFlag(flag))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .navigationTitle("Edit Flags")
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
                    Button("Save") {
                        saveFlags()
                    }
                }
            }
        }
        .onAppear {
            selectedFlags = Set(line.flags)
        }
    }
    
    private func toggleFlag(_ flag: ScriptLineFlags) {
        if selectedFlags.contains(flag) {
            selectedFlags.remove(flag)
        } else {
            selectedFlags.insert(flag)
        }
    }
    
    private func saveFlags() {
        line.flags = Array(selectedFlags)
        onSave()
        dismiss()
    }
    
    private func iconForFlag(_ flag: ScriptLineFlags) -> String {
        switch flag {
        case .stageDirection:
            return "theatermasks"
        case .skip:
            return "forward.fill"
        }
    }
    
    private func labelForFlag(_ flag: ScriptLineFlags) -> String {
        switch flag {
        case .stageDirection:
            return "Stage Direction"
        case .skip:
            return "Skip Line"
        }
    }
    
    private func colorForFlag(_ flag: ScriptLineFlags) -> Color {
        switch flag {
        case .stageDirection:
            return .purple
        case .skip:
            return .red
        }
    }
    
    private func descriptionForFlag(_ flag: ScriptLineFlags) -> String {
        switch flag {
        case .stageDirection:
            return "Mark as stage direction"
        case .skip:
            return "Skip during performance"
        }
    }
}

struct BulkFlagEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let lines: [ScriptLine]
    let onSave: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Selected Lines (\(lines.count))")) {
                    ForEach(lines.prefix(5), id: \.id) { line in
                        Text("Line \(line.lineNumber): \(line.content.prefix(50))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if lines.count > 5 {
                        Text("... and \(lines.count - 5) more lines")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Bulk Flag Operations"), footer: Text("Toggle removes flags from lines that have them, adds to lines that don't")) {
                    ForEach(ScriptLineFlags.allCases, id: \.self) { flag in
                        HStack {
                            Button(action: {
                                toggleBulkFlag(flag)
                            }) {
                                HStack {
                                    let flagStatus = getBulkFlagStatus(for: flag)
                                    Image(systemName: flagStatus.icon)
                                        .foregroundColor(flagStatus.color)
                                    
                                    HStack(spacing: 8) {
                                        Image(systemName: iconForFlag(flag))
                                            .foregroundColor(colorForFlag(flag))
                                        
                                        VStack(alignment: .leading) {
                                            Text(labelForFlag(flag))
                                                .foregroundColor(.primary)
                                            Text(flagStatus.description)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Text(descriptionForFlag(flag))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .navigationTitle("Bulk Edit Flags")
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
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func getBulkFlagStatus(for flag: ScriptLineFlags) -> (icon: String, color: Color, description: String) {
        let linesWithFlag = lines.filter { $0.flags.contains(flag) }
        let linesWithoutFlag = lines.filter { !$0.flags.contains(flag) }
        
        if linesWithFlag.count == lines.count {
            return ("checkmark.circle.fill", .green, "All lines have this flag")
        } else if linesWithFlag.isEmpty {
            return ("circle", .gray, "No lines have this flag")
        } else {
            return ("minus.circle.fill", .orange, "\(linesWithFlag.count) of \(lines.count) lines have this flag")
        }
    }
    
    private func toggleBulkFlag(_ flag: ScriptLineFlags) {
        let linesWithFlag = lines.filter { $0.flags.contains(flag) }
        
        if linesWithFlag.isEmpty {
            // No lines have the flag - add to all
            for line in lines {
                if !line.flags.contains(flag) {
                    line.flags.append(flag)
                }
            }
        } else {
            // Some lines have the flag - remove from all that have it
            for line in linesWithFlag {
                line.flags.removeAll { $0 == flag }
            }
        }
        
        onSave()
    }
    
    private func iconForFlag(_ flag: ScriptLineFlags) -> String {
        switch flag {
        case .stageDirection:
            return "theatermasks"
        case .skip:
            return "forward.fill"
        }
    }
    
    private func labelForFlag(_ flag: ScriptLineFlags) -> String {
        switch flag {
        case .stageDirection:
            return "Stage Direction"
        case .skip:
            return "Skip Line"
        }
    }
    
    private func colorForFlag(_ flag: ScriptLineFlags) -> Color {
        switch flag {
        case .stageDirection:
            return .purple
        case .skip:
            return .red
        }
    }
    
    private func descriptionForFlag(_ flag: ScriptLineFlags) -> String {
        switch flag {
        case .stageDirection:
            return "Mark as stage direction"
        case .skip:
            return "Skip during performance"
        }
    }
}

struct AddLineView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let insertAfterLineNumber: Int?
    let script: Script
    let onComplete: () -> Void
    
    @State private var newLineText = ""
    @State private var lineType: LineType = .dialogue
    @State private var selectedFlags: Set<ScriptLineFlags> = []
    
    enum LineType: String, CaseIterable {
        case dialogue = "Dialogue"
        case stageDirection = "Stage Direction"
        case character = "Character Name"
        case sceneDescription = "Scene Description"
        
        var prefix: String {
            switch self {
            case .dialogue: return ""
            case .stageDirection: return "("
            case .character: return ""
            case .sceneDescription: return "["
            }
        }
        
        var suffix: String {
            switch self {
            case .dialogue: return ""
            case .stageDirection: return ")"
            case .character: return ":"
            case .sceneDescription: return "]"
            }
        }
        
        var suggestedFlags: [ScriptLineFlags] {
            switch self {
            case .stageDirection:
                return [.stageDirection]
            default:
                return []
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Line Content")) {
                    TextField("Enter line text", text: $newLineText, axis: .vertical)
                        .lineLimit(3)
                }
                
                Section(header: Text("Line Type")) {
                    Picker("Type", selection: $lineType) {
                        ForEach(LineType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: lineType) { _, newType in
                        // Auto-select flags based on line type
                        selectedFlags = Set(newType.suggestedFlags)
                    }
                }
                
                Section(header: Text("Flags")) {
                    ForEach(ScriptLineFlags.allCases, id: \.self) { flag in
                        HStack {
                            Button(action: {
                                toggleFlag(flag)
                            }) {
                                HStack {
                                    Image(systemName: selectedFlags.contains(flag) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedFlags.contains(flag) ? .blue : .gray)
                                    
                                    HStack(spacing: 8) {
                                        Image(systemName: iconForFlag(flag))
                                            .foregroundColor(colorForFlag(flag))
                                        Text(labelForFlag(flag))
                                            .foregroundColor(.primary)
                                    }
                                    
                                    Spacer()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                Section(header: Text("Preview")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(lineType.prefix + newLineText + lineType.suffix)
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        if !selectedFlags.isEmpty {
                            HStack {
                                ForEach(Array(selectedFlags), id: \.self) { flag in
                                    HStack(spacing: 2) {
                                        Image(systemName: iconForFlag(flag))
                                            .font(.caption2)
                                        Text(labelForFlag(flag))
                                            .font(.caption2)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(colorForFlag(flag))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
                
                if let insertAfter = insertAfterLineNumber {
                    Section {
                        Text("Inserting after line \(insertAfter)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Add Line")
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
                        addLine()
                    }
                    .disabled(newLineText.isEmpty)
                }
            }
        }
        .onAppear {
            selectedFlags = Set(lineType.suggestedFlags)
        }
    }
    
    private func toggleFlag(_ flag: ScriptLineFlags) {
        if selectedFlags.contains(flag) {
            selectedFlags.remove(flag)
        } else {
            selectedFlags.insert(flag)
        }
    }
    
    private func addLine() {
        let formattedText = lineType.prefix + newLineText + lineType.suffix
        let newLineNumber = (insertAfterLineNumber ?? script.lines.count) + 1
        
        for line in script.lines where line.lineNumber >= newLineNumber {
            line.lineNumber += 1
        }
        
        let newLine = ScriptLine(
            id: UUID(),
            lineNumber: newLineNumber,
            content: formattedText,
            flags: Array(selectedFlags)
        )
        
        script.lines.append(newLine)
        
        try? modelContext.save()
        onComplete()
        dismiss()
    }
    
    private func iconForFlag(_ flag: ScriptLineFlags) -> String {
        switch flag {
        case .stageDirection:
            return "theatermasks"
        case .skip:
            return "forward.fill"
        }
    }
    
    private func labelForFlag(_ flag: ScriptLineFlags) -> String {
        switch flag {
        case .stageDirection:
            return "Stage"
        case .skip:
            return "Skip"
        }
    }
    
    private func colorForFlag(_ flag: ScriptLineFlags) -> Color {
        switch flag {
        case .stageDirection:
            return .purple
        case .skip:
            return .red
        }
    }
}
