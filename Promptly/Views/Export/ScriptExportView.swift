//
//  ScriptPDFExporterView.swift
//  Promptly
//
//  Export script with cues and sections marked as PDF
//

#if os(iOS)
import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct ScriptPDFExporterView: View {
    let script: Script
    @Environment(\.dismiss) private var dismiss
    
    @State private var isExporting = false
    @State private var showingShareSheet = false
    @State private var exportedPDFURL: URL?
    @State private var errorMessage: String?
    
    // Export options
    @State private var includeCues = true
    @State private var includeSections = true
    @State private var includeLineNumbers = true
    @State private var colorCodeCues = true
    @State private var colorCodeSections = true
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                VStack(spacing: 20) {
                    if isExporting {
                        exportingView
                    } else {
                        optionsView
                    }
                }
                .padding()
            }
            .navigationTitle("Export PDF")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                if !isExporting {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Export") {
                            exportPDF()
                        }
                        .disabled(isExporting)
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportedPDFURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }
    
    private var optionsView: some View {
        Form {
            Section("Script Info") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(script.name)
                        .font(.headline)
                    
                    Text("\(script.lines.count) lines")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(script.sections.count) sections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    let totalCues = script.lines.reduce(0) { $0 + $1.cues.count }
                    Text("\(totalCues) cues")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Export Options") {
                Toggle("Include Line Numbers", isOn: $includeLineNumbers)
                Toggle("Include Cues", isOn: $includeCues)
                Toggle("Include Section Markers", isOn: $includeSections)
            }
            
            Section("Formatting") {
                Toggle("Color-Code Cues", isOn: $colorCodeCues)
                    .disabled(!includeCues)
                
                Toggle("Color-Code Sections", isOn: $colorCodeSections)
                    .disabled(!includeSections)
            }
            
            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
    }
    
    private var exportingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Exporting PDF...")
                .font(.headline)
            
            Text("Formatting script with cues and sections")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func exportPDF() {
        isExporting = true
        errorMessage = nil
        
        Task {
            do {
                let pdfURL = try await generatePDF()
                
                await MainActor.run {
                    exportedPDFURL = pdfURL
                    isExporting = false
                    showingShareSheet = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to export PDF: \(error.localizedDescription)"
                    isExporting = false
                }
            }
        }
    }
    
    private func generatePDF() async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let pdfURL = try self.createPDFDocument()
                    continuation.resume(returning: pdfURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func createPDFDocument() throws -> URL {
        let pageSize = CGSize(width: 612, height: 792)
        let margin: CGFloat = 50
        let contentWidth = pageSize.width - (margin * 2)
        let lineHeight: CGFloat = 18
        let sectionSpacing: CGFloat = 30
        let cueIndent: CGFloat = 40

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(script.name.replacingOccurrences(of: " ", with: "_"))_\(Date().timeIntervalSince1970)_PromptlyExport.pdf"
        let pdfURL = tempDir.appendingPathComponent(fileName)

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))

        try renderer.writePDF(to: pdfURL) { context in
            var currentY: CGFloat = margin
            context.beginPage()

            func startNewPageIfNeeded(extraHeight: CGFloat) {
                if currentY + extraHeight > pageSize.height - margin {
                    context.beginPage()
                    currentY = margin
                }
            }

            let titleFont = UIFont.boldSystemFont(ofSize: 24)
            let title = NSAttributedString(string: script.name, attributes: [.font: titleFont, .foregroundColor: UIColor.black])
            title.draw(at: CGPoint(x: margin, y: currentY))
            currentY += title.size().height + 30

            let sortedSections = script.sections.sorted { $0.startLineNumber < $1.startLineNumber }
            let sortedLines = script.lines.sorted { $0.lineNumber < $1.lineNumber }
            var sectionIndex = 0

            for line in sortedLines {
                startNewPageIfNeeded(extraHeight: 100)

                if includeSections, sectionIndex < sortedSections.count {
                    let section = sortedSections[sectionIndex]
                    if section.startLineNumber == line.lineNumber {
                        let sectionText = "■ \(section.title)"
                        let sectionFont = UIFont.boldSystemFont(ofSize: 16)
                        let sectionColor = colorCodeSections ? UIColor(hex: section.type.color) : .black
                        let sectionAttr = NSAttributedString(string: sectionText, attributes: [.font: sectionFont, .foregroundColor: sectionColor])
                        sectionAttr.draw(at: CGPoint(x: margin, y: currentY))
                        currentY += sectionAttr.size().height + sectionSpacing
                        sectionIndex += 1
                    }
                }

                var textX = margin
                if includeLineNumbers {
                    let lineNumberStr = NSAttributedString(string: "\(line.lineNumber)", attributes: [
                        .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                        .foregroundColor: UIColor.gray
                    ])
                    lineNumberStr.draw(at: CGPoint(x: textX, y: currentY))
                    textX += 40
                }

                if includeCues {
                    for cue in line.cues.filter({ $0.position.offset == .before }) {
                        let cueText = "→ \(cue.type.displayName): \(cue.label)"
                        let cueColor = colorCodeCues ? UIColor(hex: cue.type.color) : .blue
                        let attr = NSAttributedString(string: cueText, attributes: [.font: UIFont.boldSystemFont(ofSize: 10), .foregroundColor: cueColor])
                        attr.draw(at: CGPoint(x: textX + cueIndent, y: currentY))
                        currentY += attr.size().height + 2
                    }
                }

                let lineFont = UIFont.systemFont(ofSize: 12)
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.lineBreakMode = .byWordWrapping
                let lineAttr: [NSAttributedString.Key: Any] = [
                    .font: lineFont,
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraphStyle
                ]
                let maxWidth = contentWidth - (textX - margin)
                let lineString = NSAttributedString(string: line.content, attributes: lineAttr)
                let boundingRect = lineString.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil)
                lineString.draw(with: CGRect(x: textX, y: currentY, width: maxWidth, height: boundingRect.height), options: [.usesLineFragmentOrigin], context: nil)
                currentY += boundingRect.height + 2

                if includeCues {
                    for cue in line.cues.filter({ $0.position.offset == .after }) {
                        let cueText = "→ \(cue.type.displayName): \(cue.label)"
                        let cueColor = colorCodeCues ? UIColor(hex: cue.type.color) : .blue
                        let attr = NSAttributedString(string: cueText, attributes: [.font: UIFont.boldSystemFont(ofSize: 10), .foregroundColor: cueColor])
                        attr.draw(at: CGPoint(x: textX + cueIndent, y: currentY))
                        currentY += attr.size().height + 2
                    }
                }

                currentY += 5
            }
        }

        return pdfURL
    }
    private func wrapText(_ text: String, maxWidth: CGFloat, font: UIFont) -> [String] {
        let words = text.components(separatedBy: .whitespaces)
        var lines: [String] = []
        var currentLine = ""
        
        for word in words {
            let testLine = currentLine.isEmpty ? word : "\(currentLine) \(word)"
            let size = testLine.size(withAttributes: [.font: font])
            
            if size.width <= maxWidth {
                currentLine = testLine
            } else {
                if !currentLine.isEmpty {
                    lines.append(currentLine)
                    currentLine = word
                } else {
                    // Word is too long, just add it anyway
                    lines.append(word)
                }
            }
        }
        
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }
        
        return lines.isEmpty ? [""] : lines
    }
    
    private func drawSectionHeader(
        context: CGContext,
        section: ScriptSection,
        x: CGFloat,
        y: inout CGFloat,
        width: CGFloat,
        colorCode: Bool
    ) {
        let sectionColor = colorCode ? UIColor(hex: section.type.color) : UIColor.black
        
        let sectionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 16),
            .foregroundColor: sectionColor
        ]
        
        let sectionText = "■ \(section.title)"
        let sectionSize = sectionText.size(withAttributes: sectionAttributes)
        
        // Draw background if color coding
        if colorCode {
            context.setFillColor(sectionColor.withAlphaComponent(0.1).cgColor)
            context.fill(CGRect(x: x, y: y - 2, width: width, height: sectionSize.height + 4))
        }
        
        sectionText.draw(at: CGPoint(x: x, y: y), withAttributes: sectionAttributes)
        y += sectionSize.height
    }
    
    private func drawCue(
        context: CGContext,
        cue: Cue,
        x: CGFloat,
        y: inout CGFloat,
        width: CGFloat,
        colorCode: Bool
    ) {
        let cueColor = colorCode ? UIColor(hex: cue.type.color) : UIColor.blue
        
        let cueAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: cueColor
        ]
        
        let cueText = "→ \(cue.type.displayName): \(cue.label)"
        
        // Draw background if color coding
        if colorCode {
            let cueSize = cueText.size(withAttributes: cueAttributes)
            context.setFillColor(cueColor.withAlphaComponent(0.1).cgColor)
            context.fill(CGRect(x: x - 5, y: y - 1, width: cueSize.width + 10, height: cueSize.height + 2))
        }
        
        cueText.draw(at: CGPoint(x: x, y: y), withAttributes: cueAttributes)
    }
}

// MARK: - UIColor extension for hex colors


// MARK: - Error types
enum ExportError: Error, LocalizedError {
    case pdfCreationFailed
    case fileWriteFailed

    var errorDescription: String? {
        switch self {
        case .pdfCreationFailed:
            return "Failed to create PDF document"
        case .fileWriteFailed:
            return "Failed to write PDF file"
        }
    }
}
#endif
