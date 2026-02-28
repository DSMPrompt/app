//
//  AddShowView.swift
//  Promptly
//
//  Created by Sasha Bagrov on 04/06/2025.
//

import SwiftUI
import SwiftData
import PDFKit

struct AddShowViewWrapper: View {
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        AddShowView(parser: PDFScriptParser(modelContext: modelContext))
    }
}

struct AddShowView: View {
    @ObservedObject var parser: PDFScriptParser
    
    @Environment(\.modelContext) var modelContext
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var location: String = ""
    @State private var performanceDates: [Date] = [Date()]
    @State private var selectedPDF: URL?
    @State private var isShowingFilePicker = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    
    @State private var creatingScript: Bool = false
    
    @State private var isError: Bool = false
    @State private var isAnimating = false
    
    @State private var progress: Double = 0.0
    
    var body: some View {
        NavigationView {
            Group {
                if creatingScript {
                    loadingView
                } else {
                    formView
                }
            }
            .toolbar {
                if !creatingScript {
                    toolbarContent
                }
            }
        }
        .interactiveDismissDisabled()
        .onReceive(parser.$progress) { newValue in
            withAnimation(.easeInOut) {
                self.progress = newValue
            }
        }
    }

    private var formView: some View {
        Form {
            showDetailsSection
            performanceDatesSection
            scriptSection
            errorSection
        }
        .navigationTitle("New Show")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileImportResult(result)
        }
    }

    private var showDetailsSection: some View {
        Section(header: Text("Show Details")) {
            TextField("Show Title", text: $title)
            TextField("Venue/Location", text: $location)
        }
    }

    private var performanceDatesSection: some View {
        Section(header: Text("Performance Dates")) {
            ForEach(Array(performanceDates.enumerated()), id: \.offset) { index, date in
                DatePicker("Performance \(index + 1)", selection: Binding(
                    get: { performanceDates[index] },
                    set: { performanceDates[index] = $0 }
                ), displayedComponents: [.date, .hourAndMinute])
            }
            .onDelete(perform: removePerformanceDates)
            
            Button("Add Performance Date") {
                performanceDates.append(Date())
            }
        }
    }

    private var scriptSection: some View {
        Section(header: Text("Script")) {
            HStack {
                VStack(alignment: .leading) {
                    if let pdfURL = selectedPDF {
                        Text("Selected: \(pdfURL.lastPathComponent)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No script selected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Choose PDF") {
                    isShowingFilePicker = true
                }
                .buttonStyle(.bordered)
                .focusable()
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let error = errorMessage {
            Section {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            if let error = errorMessage {
                VStack {
                    Image(systemName: "xmark.square")
                        .font(.system(size: 100))
                        .foregroundStyle(.red)
                        .rotationEffect(.degrees(isAnimating ? -3 : 3), anchor: .center)
                        .animation(.easeInOut(duration: 0.1), value: isAnimating)
                        .onAppear {
                            isAnimating = true
                            self.isError = true
                        }
                    
                    Text("Error")
                        .font(.largeTitle)
                        .bold()
                    
                    Text("We encountered an error while processing your script. Please try again later.")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    
                    DisclosureGroup {
                        Text(error)
                    } label: {
                        Label("Technical Details", systemImage: "hammer")
                    }
                }
                .padding(.horizontal)
            } else {
                Image(systemName: "wand.and.sparkles")
                    .font(.system(size: 100))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.purple)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
                    .onAppear {
                        isAnimating = true
                    }
                    .onDisappear {
                        isAnimating = false
                    }
                
                Text("Generating...")
                    .font(.largeTitle)
                    .bold()
                
                Text("Converting your script to a show...")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                
                Divider()
                    .padding([.horizontal, .vertical])
                
                // Status updates using Vision parser
                Text("Page \(parser.currentPage) of \(parser.totalPages)")
                    .font(.headline)
                
                ProgressView("Processing PDF with Vision...", value: self.progress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .padding()
            }
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .interactiveDismissDisabled(!self.isError)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel") {
                dismiss()
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Create") {
                createShow()
            }
            .disabled(!canCreateShow || isProcessing)
        }
        #else
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                dismiss()
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("Create") {
                createShow()
            }
            .disabled(!canCreateShow || isProcessing)
        }
        #endif
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedPDF = url
                errorMessage = nil
            }
        case .failure(let error):
            errorMessage = "Failed to select PDF: \(error.localizedDescription)"
        }
    }
    
    private var canCreateShow: Bool {
        !title.isEmpty && !location.isEmpty && selectedPDF != nil
    }
    
    private func createShow() {
        guard let pdfURL = selectedPDF else {
            errorMessage = "Please select a PDF script"
            return
        }
        
        isProcessing = true
        errorMessage = nil
        
        Task {
            do {
                let script = try await processPDFToScript(url: pdfURL)
                
                guard let script = script else {
                    throw PDFProcessingError.processingFailed
                }
                
                let performances = createPerformances()
                
                await MainActor.run {
                    let show = Show(
                        id: UUID(),
                        title: title,
                        dates: performanceDates,
                        locationString: location,
                        script: script,
                        peformances: performances
                    )
                    
                    // Set up the relationship properly
                    show.script = script
                    
                    modelContext.insert(show)
                    modelContext.insert(script)
                    
                    do {
                        try modelContext.save()
                        dismiss()
                    } catch {
                        errorMessage = "Failed to save show: \(error.localizedDescription)"
                        isProcessing = false
                        creatingScript = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to process PDF: \(error.localizedDescription)"
                    isProcessing = false
                    creatingScript = false
                }
            }
        }
    }
    
    private func processPDFToScript(url: URL) async throws -> Script? {
        await MainActor.run {
            withAnimation(.easeInOut) {
                self.creatingScript = true
            }
        }
        
        guard url.startAccessingSecurityScopedResource() else {
            throw PDFProcessingError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard let pdfDocument = PDFDocument(url: url) else {
            throw PDFProcessingError.invalidPDF
        }
        
        print(pdfDocument.pageCount)
        
        // Use the Vision-based parser
        let scriptName = url.deletingPathExtension().lastPathComponent
        let script = try await parser.parseScript(from: pdfDocument, scriptName: scriptName)
        
        // Analyze structure
        parser.analyzeScriptStructure(script)
        
        return script
    }
    
    private func createPerformances() -> [Performance] {
        return performanceDates.map { date in
            Performance(
                id: UUID(),
                date: date,
                calls: []
            )
        }
    }
    
    private func removePerformanceDates(offsets: IndexSet) {
        performanceDates.remove(atOffsets: offsets)
    }
}
