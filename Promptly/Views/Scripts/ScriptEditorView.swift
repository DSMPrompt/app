//
//  ScriptEditorView.swift
//  Promptly
//
//  Created by Sasha Bagrov on 04/06/2025.
//

import SwiftUI
import SwiftData

struct ScriptEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let script: Script
    @State private var selectedLine: ScriptLine?
    @State private var selectedElement: LineElement?
    @State private var isShowingCueEditor = false
    @State private var isShowingMarkingTools = false
    @State private var editingLineId: UUID?
    @State private var editingText: String = ""
    @State private var showingDeleteCueAlert = false
    @State private var cueToDelete: Cue?
    
    private var sortedLines: [ScriptLine] {
        script.lines.sorted(by: { $0.lineNumber < $1.lineNumber })
    }

    private func handleCueEdit(cue: Cue) {
        guard let line = script.lines.first(where: { $0.id == cue.lineId }) else { return }
        selectedLine = line
        selectedElement = line.elements.first(where: { $0.position == cue.position.elementIndex })
        isShowingCueEditor = true
    }
    
    var body: some View {
        VStack(spacing: 0) {
            scriptContentView
        }
        .sheet(isPresented: $isShowingCueEditor) {
            if let line = selectedLine, let element = selectedElement {
                CueEditorView(line: line, element: element)
            }
        }
        .sheet(isPresented: $isShowingMarkingTools) {
            MarkingToolsView(selectedLine: selectedLine, selectedElement: selectedElement)
        }
        .alert("Delete Cue", isPresented: $showingDeleteCueAlert) {
            Button("Cancel", role: .cancel) {
                cueToDelete = nil
            }
            Button("Delete", role: .destructive) {
                deleteCue()
            }
        } message: {
            if let cue = cueToDelete {
                Text("Are you sure you want to delete the cue '\(cue.label)'? This action cannot be undone.")
            }
        }
        .navigationTitle(Text(script.name))
        .toolbar {
            ToolbarItem {
                Button("Tools") {
                    isShowingMarkingTools = true
                }
            }
        }
    }
    
    private var scriptContentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sortedLines, id: \.id) { line in
                        ScriptLineView(
                            line: line,
                            isSelected: selectedLine?.id == line.id,
                            isEditing: editingLineId == line.id,
                            editingText: $editingText,
                            onElementTap: { element in
                                handleElementTap(element: element, line: line)
                            },
                            onLineTap: {
                                handleLineTap(line: line)
                            },
                            onEditComplete: { newText in
                                updateLineContent(line: line, newText: newText)
                            },
                            onCueDelete: handleCueDelete,
                            onCueEdit: handleCueEdit
                        )
                        .id("line-\(line.id)")
                    }
                }
                .padding()
            }
        }
    }
    
    private func handleElementTap(element: LineElement, line: ScriptLine) {
        selectedLine = line
        selectedElement = element
        isShowingCueEditor = true
    }
    
    private func handleLineTap(line: ScriptLine) {
        if editingLineId == line.id {
            editingLineId = nil
        } else {
            selectedLine = line
            editingLineId = line.id
            editingText = line.content
        }
    }
    
    private func updateLineContent(line: ScriptLine, newText: String) {
        line.content = newText
        line.parseContentIntoElements()
        editingLineId = nil
        try? modelContext.save()
    }
    
    private func handleCueDelete(cue: Cue) {
        cueToDelete = cue
        showingDeleteCueAlert = true
    }
    
    private func deleteCue() {
        guard let cue = cueToDelete,
              let line = script.lines.first(where: { $0.cues.contains(where: { $0.id == cue.id }) }) else {
            return
        }
        
        line.cues.removeAll { $0.id == cue.id }
        modelContext.delete(cue)
        
        try? modelContext.save()
        cueToDelete = nil
    }
}

struct ScriptLineView: View, Equatable {
    let line: ScriptLine
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editingText: String
    let onElementTap: (LineElement) -> Void
    let onLineTap: () -> Void
    let onEditComplete: (String) -> Void
    let onCueDelete: ((Cue) -> Void)?
    let onCueEdit: ((Cue) -> Void)?
    
    init(
        line: ScriptLine,
        isSelected: Bool,
        isEditing: Bool,
        editingText: Binding<String>,
        onElementTap: @escaping (LineElement) -> Void,
        onLineTap: @escaping () -> Void,
        onEditComplete: @escaping (String) -> Void,
        onCueDelete: ((Cue) -> Void)? = nil,
        onCueEdit: ((Cue) -> Void)? = nil
    ) {
        self.line = line
        self.isSelected = isSelected
        self.isEditing = isEditing
        self._editingText = editingText
        self.onElementTap = onElementTap
        self.onLineTap = onLineTap
        self.onEditComplete = onEditComplete
        self.onCueDelete = onCueDelete
        self.onCueEdit = onCueEdit
    }
    
    static func == (lhs: ScriptLineView, rhs: ScriptLineView) -> Bool {
        lhs.line.id == rhs.line.id &&
        lhs.line.content == rhs.line.content &&
        lhs.line.lineNumber == rhs.line.lineNumber &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isEditing == rhs.isEditing &&
        lhs.editingText == rhs.editingText
    }
    
    private var sortedCues: [Cue] {
        line.cues.sorted(by: { $0.position.elementIndex < $1.position.elementIndex })
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(line.lineNumber)")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
                .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Line content", text: $editingText, onCommit: {
                        onEditComplete(editingText)
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                } else {
                    LineContentView(
                        line: line,
                        onElementTap: onElementTap,
                        onLineTap: onLineTap,
                        onCueDelete: onCueDelete
                    )
                }
                
                if !line.cues.isEmpty {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(sortedCues, id: \.id) { cue in
                            CueDisplayView(
                                cue: cue,
                                onDelete: onCueDelete,
                                onEdit: onCueEdit
                            )
                        }
                    }
                }
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
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
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
        line.isMarked ? 0.3 : (isSelected ? 0.5 : 0.1)
    }
}

struct LineContentView: View, Equatable {
    let line: ScriptLine
    let onElementTap: (LineElement) -> Void
    let onLineTap: () -> Void
    let onCueDelete: ((Cue) -> Void)?
    
    init(line: ScriptLine, onElementTap: @escaping (LineElement) -> Void, onLineTap: @escaping () -> Void, onCueDelete: ((Cue) -> Void)? = nil) {
        self.line = line
        self.onElementTap = onElementTap
        self.onLineTap = onLineTap
        self.onCueDelete = onCueDelete
    }
    
    static func == (lhs: LineContentView, rhs: LineContentView) -> Bool {
        lhs.line.id == rhs.line.id &&
        lhs.line.content == rhs.line.content
    }
    
    private var sortedElements: [LineElement] {
        line.elements.sorted(by: { $0.position < $1.position })
    }
    
    var body: some View {
        Button(action: onLineTap) {
            FlowLayout(spacing: 2) {
                ForEach(sortedElements, id: \.id) { element in
                    ElementWithCuesView(
                        element: element,
                        line: line,
                        onElementTap: onElementTap,
                        onCueDelete: onCueDelete
                    )
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ElementWithCuesView: View {
    let element: LineElement
    let line: ScriptLine
    let onElementTap: (LineElement) -> Void
    let onCueDelete: ((Cue) -> Void)?
    
    init(element: LineElement, line: ScriptLine, onElementTap: @escaping (LineElement) -> Void, onCueDelete: ((Cue) -> Void)? = nil) {
        self.element = element
        self.line = line
        self.onElementTap = onElementTap
        self.onCueDelete = onCueDelete
    }
    
    private var cuesBefore: [Cue] {
        line.cues.filter {
            $0.position.elementIndex == element.position && $0.position.offset == .before
        }
    }
    
    private var cuesAfter: [Cue] {
        line.cues.filter {
            $0.position.elementIndex == element.position && $0.position.offset == .after
        }
    }
    
    var body: some View {
        HStack(spacing: 1) {
            ForEach(cuesBefore, id: \.id) { cue in
                CueIndicator(cue: cue, onDelete: onCueDelete)
            }
            
            Button(element.content.isEmpty ? " " : element.content) {
                onElementTap(element)
            }
            .foregroundColor(.primary)
            .background(
                element.isMarked ?
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: element.markColor ?? "#FFFF00"))
                    .opacity(0.4) :
                nil
            )
            .font(.body)
            
            ForEach(cuesAfter, id: \.id) { cue in
                CueIndicator(cue: cue, onDelete: onCueDelete)
            }
        }
    }
}

struct CueIndicator: View {
    let cue: Cue
    let onDelete: ((Cue) -> Void)?
    
    init(cue: Cue, onDelete: ((Cue) -> Void)? = nil) {
        self.cue = cue
        self.onDelete = onDelete
    }
    
    var body: some View {
        Text(cue.label)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: cue.type.color))
                    .opacity(0.8)
            )
            .foregroundColor(.black)
            .onLongPressGesture {
                if let onDelete = onDelete {
                    onDelete(cue)
                }
            }
    }
}

struct CueDisplayView: View {
    let cue: Cue
    let onDelete: ((Cue) -> Void)?
    let onEdit: ((Cue) -> Void)?
    
    init(cue: Cue, onDelete: ((Cue) -> Void)? = nil, onEdit: ((Cue) -> Void)? = nil) {
        self.cue = cue
        self.onDelete = onDelete
        self.onEdit = onEdit
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: cue.type.color))
                .frame(width: 6, height: 6)
            
            Text("\(cue.type.displayName): \(cue.label)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if cue.hasAlert {
                Image(systemName: "bell.fill")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
            
            Spacer()
            
            if let onEdit = onEdit {
                Button(action: {
                    onEdit(cue)
                }) {
                    Image(systemName: "pencil")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }

            if let onDelete = onDelete {
                Button(action: {
                    onDelete(cue)
                }) {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onLongPressGesture {
            if let onDelete = onDelete {
                onDelete(cue)
            }
        }
    }
}

struct FlowLayout: Layout {
    let spacing: CGFloat
    
    init(spacing: CGFloat = 8) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                    y: bounds.minY + result.frames[index].minY),
                         proposal: ProposedViewSize(result.frames[index].size))
        }
    }
}

struct FlowResult {
    let size: CGSize
    let frames: [CGRect]
    
    init(in maxWidth: CGFloat, subviews: LayoutSubviews, spacing: CGFloat) {
        var frames: [CGRect] = []
        var currentRowY: CGFloat = 0
        var currentRowX: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentRowX + size.width > maxWidth && currentRowX > 0 {
                currentRowY += currentRowHeight + spacing
                currentRowX = 0
                currentRowHeight = 0
            }
            
            frames.append(CGRect(x: currentRowX, y: currentRowY, width: size.width, height: size.height))
            currentRowX += size.width + spacing
            currentRowHeight = max(currentRowHeight, size.height)
        }
        
        self.frames = frames
        self.size = CGSize(width: maxWidth, height: currentRowY + currentRowHeight)
    }
}
