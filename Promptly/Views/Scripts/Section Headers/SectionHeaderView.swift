//
//  SectionHeaderView.swift
//  Promptly
//
//  Created by Sasha Bagrov on 04/06/2025.
//

import SwiftUI
import SwiftData

struct SectionHeaderView: View {
    let section: ScriptSection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: section.type.color))
                    .frame(width: 6, height: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.type.displayName.uppercased())
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Text(section.title)
                        .font(.headline)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                Text("Line \(section.startLineNumber)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color(.tertiarySystemFill))
                    .cornerRadius(4)
            }
            
            if !section.notes.isEmpty {
                Text(section.notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: section.type.color).opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(hex: section.type.color).opacity(0.3), lineWidth: 1)
        )
    }
}

struct SectionDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var pendingTitle: String
    @Binding var pendingType: SectionType
    @Binding var pendingNotes: String
    let onStartSelection: (String, SectionType, String) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Section Details")) {
                    TextField("Section Title", text: $pendingTitle)
                    
                    Picker("Type", selection: $pendingType) {
                        ForEach(SectionType.allCases, id: \.self) { sectionType in
                            HStack {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(hex: sectionType.color))
                                    .frame(width: 12, height: 12)
                                Text(sectionType.displayName)
                            }
                            .tag(sectionType)
                        }
                    }
                }
                
                Section(header: Text("Quick Templates")) {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 8) {
                        SectionTemplateButton(
                            type: .act,
                            title: "Act 1"
                        ) {
                            applyTemplate(type: .act, title: "Act 1")
                        }
                        
                        SectionTemplateButton(
                            type: .scene,
                            title: "Scene 1"
                        ) {
                            applyTemplate(type: .scene, title: "Scene 1")
                        }
                        
                        SectionTemplateButton(
                            type: .preset,
                            title: "Preset Change"
                        ) {
                            applyTemplate(type: .preset, title: "Preset Change")
                        }
                        
                        SectionTemplateButton(
                            type: .songNumber,
                            title: "Musical Number"
                        ) {
                            applyTemplate(type: .songNumber, title: "Musical Number")
                        }
                    }
                }
                
                Section(header: Text("Notes (Optional)")) {
                    TextField("Section notes or description", text: $pendingNotes, axis: .vertical)
                        .lineLimit(3)
                }
            }
            .navigationTitle("Section Details")
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
                    Button("Select Line") {
                        onStartSelection(pendingTitle, pendingType, pendingNotes)
                        dismiss()
                    }
                    .disabled(pendingTitle.isEmpty)
                }
            }
        }
    }
    
    private func applyTemplate(type: SectionType, title: String) {
        pendingType = type
        pendingTitle = title
    }
}

struct SectionTemplateButton: View {
    let type: SectionType
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: type.color))
                    .frame(height: 20)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
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

struct SectionsManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingDeleteAllAlert = false
    @State private var showingAddSection = false
    @State private var isSelectingLineForSection = false
    @State private var pendingSectionType: SectionType = .scene
    @State private var pendingSectionTitle = ""
    @State private var pendingSectionNotes = ""
    @State private var showingLineConfirmation = false
    @State private var selectedLineForSection: ScriptLine?
    
    let script: Script
    let calledFromEditView: Bool
    let onStartLineSelection: ((String, SectionType, String) -> Void)?
    
    init(script: Script, calledFromEditView: Bool = false, onStartLineSelection: ((String, SectionType, String) -> Void)? = nil) {
        self.script = script
        self.calledFromEditView = calledFromEditView
        self.onStartLineSelection = onStartLineSelection
    }
    
    var sortedSections: [ScriptSection] {
        script.sections.sorted { $0.startLineNumber < $1.startLineNumber }
    }
    
    var sortedLines: [ScriptLine] {
        script.lines.sorted { $0.lineNumber < $1.lineNumber }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if isSelectingLineForSection && !calledFromEditView {
                    selectionOverlay
                }
                
                mainContentView
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
            .sheet(isPresented: $showingAddSection) {
                SectionDetailsView(
                    pendingTitle: $pendingSectionTitle,
                    pendingType: $pendingSectionType,
                    pendingNotes: $pendingSectionNotes
                ) { title, type, notes in
                    if calledFromEditView {
                        // Dismiss both sheets and delegate to EditScriptView
                        dismiss()
                        onStartLineSelection?(title, type, notes)
                    } else {
                        // Handle locally
                        pendingSectionTitle = title
                        pendingSectionType = type
                        pendingSectionNotes = notes
                        isSelectingLineForSection = true
                    }
                }
            }
        }
    }
    
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
                pendingSectionTitle = ""
                pendingSectionNotes = ""
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
        List {
            if sortedSections.isEmpty && !isSelectingLineForSection {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    
                    Text("No Sections")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Add sections to organize your script into acts, scenes, and other segments.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else if isSelectingLineForSection {
                ForEach(sortedLines) { line in
                    SelectableLineView(
                        line: line,
                        isSelected: false
                    ) {
                        selectLineForSection(line: line)
                    }
                }
            } else {
                ForEach(sortedSections) { section in
                    SectionRowView(section: section) {
                        dismiss()
                        NotificationCenter.default.post(
                            name: NSNotification.Name("ScrollToSection"),
                            object: section.id
                        )
                    }
                }
                .onDelete(perform: deleteSections)
            }
        }
        .navigationTitle(isSelectingLineForSection ? "Select Line" : "Script Sections")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }

            ToolbarItem {
                if !isSelectingLineForSection {
                    Menu {
                        Button {
                            showingAddSection = true
                        } label: {
                            Label("Add Section", systemImage: "plus")
                        }

                        Button(role: .destructive) {
                            showingDeleteAllAlert = true
                        } label: {
                            Label("Delete All", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .alert("Delete All Sections?", isPresented: $showingDeleteAllAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                deleteAllSections()
            }
        } message: {
            Text("This will permanently delete all sections from the script.")
        }
    }
    
    private func selectLineForSection(line: ScriptLine) {
        selectedLineForSection = line
        showingLineConfirmation = true
    }
    
    private func createSectionWithSelectedLine() {
        guard let line = selectedLineForSection else { return }
        
        let section = ScriptSection(
            id: UUID(),
            title: pendingSectionTitle,
            type: pendingSectionType,
            startLineNumber: line.lineNumber
        )
        section.notes = pendingSectionNotes
        
        script.sections.append(section)
        
        isSelectingLineForSection = false
        selectedLineForSection = nil
        pendingSectionTitle = ""
        pendingSectionNotes = ""
        
        try? modelContext.save()
    }
    
    private func deleteSections(offsets: IndexSet) {
        for index in offsets {
            let section = sortedSections[index]
            script.sections.removeAll { $0.id == section.id }
            modelContext.delete(section)
        }
        try? modelContext.save()
    }
    
    private func deleteAllSections() {
        for section in script.sections {
            modelContext.delete(section)
        }
        script.sections.removeAll()
        try? modelContext.save()
    }
}

struct SectionRowView: View {
    let section: ScriptSection
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: section.type.color))
                    .frame(width: 4, height: 40)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(section.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(section.type.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !section.notes.isEmpty {
                        Text(section.notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Line \(section.startLineNumber)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let endLine = section.endLineNumber {
                        Text("to \(endLine)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AddSectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    let script: Script
    let startLineNumber: Int
    
    @State private var title = ""
    @State private var type: SectionType = .scene
    @State private var notes = ""
    @State private var selectedStartLine: Int
    @State private var isSelectingLine = false
    @State private var showingLineConfirmation = false
    @State private var pendingLineSelection: Int?
    
    init(script: Script, startLineNumber: Int) {
        self.script = script
        self.startLineNumber = startLineNumber
        self._selectedStartLine = State(initialValue: startLineNumber)
    }
    
    var sortedLines: [ScriptLine] {
        script.lines.sorted { $0.lineNumber < $1.lineNumber }
    }
    
    var body: some View {
        if isSelectingLine {
            LineSelectionView(
                script: script,
                selectedLine: selectedStartLine
            ) { lineNumber in
                pendingLineSelection = lineNumber
                showingLineConfirmation = true
            } onCancel: {
                isSelectingLine = false
            }
        } else {
            NavigationView {
                Form {
                    Section(header: Text("Section Details")) {
                        TextField("Section Title", text: $title)
                        
                        Picker("Type", selection: $type) {
                            ForEach(SectionType.allCases, id: \.self) { sectionType in
                                HStack {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(hex: sectionType.color))
                                        .frame(width: 12, height: 12)
                                    Text(sectionType.displayName)
                                }
                                .tag(sectionType)
                            }
                        }
                    }
                    
                    Section(header: Text("Position")) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Start at Line")
                                    .font(.subheadline)
                                
                                Text("Line \(selectedStartLine)")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                                
                                if let line = sortedLines.first(where: { $0.lineNumber == selectedStartLine }) {
                                    Text(line.content.prefix(50) + (line.content.count > 50 ? "..." : ""))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            
                            Spacer()
                            
                            Button("Select Line") {
                                isSelectingLine = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    Section(header: Text("Notes (Optional)")) {
                        TextField("Section notes or description", text: $notes, axis: .vertical)
                            .lineLimit(3)
                    }
                    
                    Section(header: Text("Quick Templates")) {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            SectionTemplateButton(
                                type: .act,
                                title: "Act \(getNextActNumber())"
                            ) {
                                applyTemplate(type: .act, title: "Act \(getNextActNumber())")
                            }
                            
                            SectionTemplateButton(
                                type: .scene,
                                title: "Scene \(getNextSceneNumber())"
                            ) {
                                applyTemplate(type: .scene, title: "Scene \(getNextSceneNumber())")
                            }
                            
                            SectionTemplateButton(
                                type: .preset,
                                title: "Preset Change"
                            ) {
                                applyTemplate(type: .preset, title: "Preset Change")
                            }
                            
                            SectionTemplateButton(
                                type: .songNumber,
                                title: "Musical Number"
                            ) {
                                applyTemplate(type: .songNumber, title: "Musical Number")
                            }
                        }
                    }
                }
                .navigationTitle("Add Section")
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
                            addSection()
                        }
                        .disabled(title.isEmpty)
                    }
                }
                .alert("Confirm Line Selection", isPresented: $showingLineConfirmation) {
                    Button("Cancel", role: .cancel) {
                        pendingLineSelection = nil
                    }
                    Button("Confirm") {
                        if let lineNumber = pendingLineSelection {
                            selectedStartLine = lineNumber
                            isSelectingLine = false
                            pendingLineSelection = nil
                        }
                    }
                } message: {
                    if let lineNumber = pendingLineSelection,
                       let line = sortedLines.first(where: { $0.lineNumber == lineNumber }) {
                        Text("Start section at line \(lineNumber)?\n\n\"\(line.content.prefix(100))...\"")
                    }
                }
            }
        }
    }
    
    private func applyTemplate(type: SectionType, title: String) {
        self.type = type
        self.title = title
    }
    
    private func getNextActNumber() -> Int {
        let actSections = script.sections.filter { $0.type == .act }
        return actSections.count + 1
    }
    
    private func getNextSceneNumber() -> Int {
        let sceneSections = script.sections.filter { $0.type == .scene }
        return sceneSections.count + 1
    }
    
    private func addSection() {
        let section = ScriptSection(
            id: UUID(),
            title: title,
            type: type,
            startLineNumber: selectedStartLine
        )
        section.notes = notes
        
        script.sections.append(section)
        
        try? modelContext.save()
        dismiss()
    }
}

struct LineSelectionView: View {
    let script: Script
    let selectedLine: Int
    let onLineSelected: (Int) -> Void
    let onCancel: () -> Void
    
    var sortedLines: [ScriptLine] {
        script.lines.sorted { $0.lineNumber < $1.lineNumber }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Instructions
                VStack(spacing: 8) {
                    Text("Select Start Line")
                        .font(.headline)
                    
                    Text("Tap a line to mark where this section begins")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                #if os(iOS)
                .background(Color(uiColor: .systemGroupedBackground))
                #endif
                #if os(macOS)
                .background(Color(nsColor: .windowBackgroundColor))
                #endif
                
                // Script lines
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(sortedLines) { line in
                            SelectableLineView(
                                line: line,
                                isSelected: line.lineNumber == selectedLine
                            ) {
                                onLineSelected(line.lineNumber)
                            }
                        }
                    }
                    .padding()
                }
                #if os(iOS)
                .background(Color(uiColor: .systemGroupedBackground))
                #endif
                #if os(macOS)
                .background(Color(nsColor: .windowBackgroundColor))
                #endif
            }
            .navigationTitle("Select Line")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }
}

struct SelectableLineView: View {
    let line: ScriptLine
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                // Line number
                Text("\(line.lineNumber)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .secondary)
                    .frame(width: 30, alignment: .trailing)
                
                // Line content
                Text(line.content)
                    .font(.body)
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    #if os(iOS)
                    .fill(isSelected ? Color.blue : Color(uiColor: .secondarySystemGroupedBackground))
                    #endif
                    #if os(macOS)
                    .fill(isSelected ? Color.blue : Color(nsColor: .controlBackgroundColor))
                    #endif
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue.opacity(0.3), lineWidth: isSelected ? 2 : 0)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
