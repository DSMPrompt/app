//
//  ShowDetailView.swift
//  Promptly
//
//  Created by Sasha Bagrov on 04/06/2025.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MIDIKitIO

extension UTType {
    static var dsmPrompt: UTType {
        UTType(exportedAs: "com.promptly.dsmprompt")
    }
}

struct ShowDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ObservableMIDIManager.self) private var midiManager
    @Environment(MIDIHelper.self) private var midiHelper
    
    let show: Show
    @State private var isShowingEditShow: Bool = false
    @State private var isShowingDeleteAlert: Bool = false
    @State private var selectedPerformance: Performance?
    @State private var showingReports = false
    @State private var showingExportScriptSheet = false
    @State private var showingAddPerformanceSheet = false
    @State private var newPerformanceDate = Date()
    
    @State private var showPerformanceAlert: Bool = false
    @State private var performanceToStart: Performance? = nil
    
    @State private var showingExportShowSheet = false
    @State private var exportError: ExportError1?
    
    @Query private var performanceReports: [PerformanceReport]
    
    
    var reportsForThisShow: [PerformanceReport] {
        let reports = performanceReports.filter { report in
            show.peformances.contains { $0.id == report.performanceId }
        }
        print("🔍 Found \(reports.count) reports for show '\(show.title)'")
        print("Show has \(show.peformances.count) performances")
        print("Total reports in database: \(performanceReports.count)")
        return reports
    }
    
    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    showHeader
                    
                    Divider()
                    
                    performanceDatesSection
                    
                    Divider()
                    
                    scriptSection
                    
                    if !reportsForThisShow.isEmpty {
                        Divider()
                        performanceReportsSection
                    }
                    
                    Divider()
                    
                    quickActionsSection
                    
                    Spacer(minLength: 50)
                }
                .padding()
            }
            #if os(iOS)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
            #endif
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("Edit Show", systemImage: "pencil") {
                            isShowingEditShow = true
                        }
                        
                        Divider()
                        
                        Button("Export Show", systemImage: "square.and.arrow.up") {
                            showingExportShowSheet = true
                        }
                        
                        Divider()
                        
                        Button("Delete Show", systemImage: "trash", role: .destructive) {
                            isShowingDeleteAlert = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isShowingEditShow) {
                EditShowView(show: show)
            }
            .sheet(item: $selectedPerformance) { performance in
                PerformanceDetailView(performance: performance)
            }
            .sheet(isPresented: $showingReports) {
                PerformanceReportsListView(reports: reportsForThisShow)
            }
            .sheet(isPresented: self.$showingExportScriptSheet, content: {
                #if os(iOS)
                Group {
                    if let script = self.show.script {
                        ScriptPDFExporterView(script: script)
                    }
                }
                #else
                Text("PDF Export not available on macOS")
                #endif
            })
            .sheet(isPresented: $showingAddPerformanceSheet) {
                NavigationView {
                    VStack(spacing: 20) {
                        Text("Add New Performance")
                            .font(.headline)
                            .padding(.top)
                        
                        DatePicker("Performance Date & Time",
                                  selection: $newPerformanceDate,
                                  displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.graphical)
                            .padding(.horizontal)
                        
                        Spacer()
                    }
                    .padding()
                    .navigationTitle("New Performance")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingAddPerformanceSheet = false
                            }
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                addPerformance(date: newPerformanceDate)
                                showingAddPerformanceSheet = false
                            }
                        }
                    }
                }
            }
            .fileExporter(
                isPresented: $showingExportShowSheet,
                document: DSMPromptDocument(show: show),
                contentType: .dsmPrompt,
                defaultFilename: "\(show.title.replacingOccurrences(of: " ", with: "_")).dsmprompt"
            ) { result in
                switch result {
                case .success(let url):
                    print("✅ Show exported successfully to: \(url)")
                case .failure(let error):
                    print("❌ Export failed: \(error)")
                    exportError = .serialisationFailed
                }
            }
            .alert("Delete Show", isPresented: $isShowingDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteShow()
                }
            } message: {
                Text("Are you sure you want to delete '\(show.title)'? This action cannot be undone.")
            }
            .alert("Export Error", isPresented: Binding<Bool>(
                get: { exportError != nil },
                set: { _ in exportError = nil }
            )) {
                Button("OK") { exportError = nil }
            } message: {
                if let error = exportError {
                    Text(error.localizedDescription)
                }
            }
            .alert("Which performance would you like to start?", isPresented: $showPerformanceAlert) {
                Button("Cancel", role: .cancel) { }
                ForEach(show.peformances) { performance in
                    Button(performance.date.formatted(date: .abbreviated, time: .shortened)) {
                        performanceToStart = performance
                    }
                }
            }
            #if os(iOS)
            .fullScreenCover(item: $performanceToStart, onDismiss: {
                performanceToStart = nil
            }, content: {
                DSMPerformanceView(performance: $0)
                    .environment(midiManager)
                    .environment(midiHelper)
                    .interactiveDismissDisabled(true)
            })
            #else
            .sheet(item: $performanceToStart, onDismiss: {
                performanceToStart = nil
            }, content: {
                DSMPerformanceView(performance: $0)
                    .environment(midiManager)
                    .environment(midiHelper)
            })
            #endif
            .onAppear {
                print("📅 Performance dates: \(show.performanceDates.count)")
                print("🎭 Performances: \(show.peformances.count)")
                for performance in self.show.peformances {
                    print(performance)
                }
            }
        }
    
    private var showHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(show.title)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Label(show.locationString, systemImage: "location")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var performanceDatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Dates")
                .font(.headline)

            LazyVStack(spacing: 8) {
                ForEach(show.performanceDates.sorted(by: { $0.date < $1.date })) { perfDate in
                    let matchedPerformance = show.peformances.first {
                        abs($0.date.timeIntervalSince(perfDate.date)) < 86400
                    }

                    PerformanceDateRow(
                        performanceDate: perfDate,
                        performance: matchedPerformance
                    ) {
                        if let performance = matchedPerformance {
                            selectedPerformance = performance
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deletePerformanceDate(for: perfDate)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                Button(action: {
                    newPerformanceDate = Date()
                    showingAddPerformanceSheet = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                        Text("Add Performance Date")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                        Spacer()
                    }
                    .padding()
                    #if os(iOS)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    #endif
                    #if os(macOS)
                    .background(Color(nsColor: .controlBackgroundColor))
                    #endif
                    .cornerRadius(8)
                }

                // Button(role: .destructive) {
                //     show.performanceDates.removeAll()
                //     show.peformances.removeAll()
                //     let today = Date()
                //     addPerformance(date: today)
                // } label: {
                //     HStack {
                //         Image(systemName: "trash")
                //             .foregroundColor(.red)
                //         Text("Delete All and Create Today")
                //             .font(.subheadline)
                //             .foregroundColor(.red)
                //         Spacer()
                //     }
                //     .padding()
                //     .background(Color.platformSecondarySystemGroupedBackground)
                //     .cornerRadius(8)
                // }
            }
        }
    }
    
    private var scriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Script")
                .font(.headline)

            if let script = show.script {
                NavigationLink(destination: ScriptEditorView(script: script)) {
                    ScriptSummaryCard(script: script)
                }
                .buttonStyle(PlainButtonStyle())
				
                NavigationLink(destination: RehearsalModeView(script: script)) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rehearsal Mode")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Fast cue capture during tech rehearsals")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                    .padding()
                    #if os(iOS)
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    #endif
                    #if os(macOS)
                    .background(Color(nsColor: .controlBackgroundColor))
                    #endif
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                EmptyScriptCard {

                }
            }
        }
    }
    
    private var performanceReportsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance Reports")
                .font(.headline)
            
            HStack {
                Text("\(reportsForThisShow.count) reports available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("View All") {
                    showingReports = true
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }
            .padding()
            #if os(iOS)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            #endif
            #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
            #endif
            .cornerRadius(8)
        }
    }
    
    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                QuickActionCard(
                    title: "Start Performance",
                    icon: "play.circle.fill",
                    color: .green
                )
                .onTapGesture {
                    self.showPerformanceAlert = true
                }
                
                if let script = self.show.script {
                    NavigationLink(destination: EditScriptView(script: script)) {
                        QuickActionCard(
                            title: "Edit Script",
                            icon: "doc.text",
                            color: .blue
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                QuickActionCard(
                    title: "Performance Reports",
                    icon: "chart.line.uptrend.xyaxis",
                    color: .orange
                )
                .onTapGesture {
                    showingReports = true
                }
                
                QuickActionCard(
                    title: "Export Script",
                    icon: "square.and.arrow.up",
                    color: .purple
                )
                .onTapGesture {
                    self.showingExportScriptSheet = true
                }
            }
        }
    }
    
    private func deleteShow() {
        modelContext.delete(show)
        dismiss()
    }
    
    private func deletePerformanceDate(for performanceDate: PerformanceDate) {
        if let index = show.performanceDates.firstIndex(of: performanceDate) {
            show.removePerformanceDate(at: index)
        }
        
        if let matchingPerformance = show.peformances.first(where: {
            abs($0.date.timeIntervalSince(performanceDate.date)) < 86400
        }) {
            show.peformances.removeAll { $0.id == matchingPerformance.id }
            modelContext.delete(matchingPerformance)
        }
    }
    
    private func addPerformance(date: Date) {
        show.addPerformanceDate(date)
        
        let performance = Performance(
            id: UUID(),
            date: date,
            calls: [],
            timing: nil,
            show: show
        )
        
        modelContext.insert(performance)
        show.peformances.append(performance)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

@preconcurrency
struct DSMPromptDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.dsmPrompt] }

    let show: Show
    
    init(show: Show) {
        self.show = show
    }
    
    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = ShowExportManager.exportShow(show) else {
            throw ExportError1.serialisationFailed
        }
        return FileWrapper(regularFileWithContents: data)
    }
}

struct PerformanceReportSummaryCard: View {
    let report: PerformanceReport
    @State private var showingFullReport = false
    
    var body: some View {
        Button(action: {
            showingFullReport = true
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.performanceDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text("Runtime: \(formatDuration(report.totalRuntime))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        StatusBadge(state: report.currentState)
                        
                        Text("\(report.callsExecuted) calls")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack {
                    Label("\(report.cuesExecuted)", systemImage: "lightbulb.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    
                    if report.showStops > 0 {
                        Label("\(report.showStops)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            #if os(iOS)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            #endif
            #if os(macOS)
            .background(Color(nsColor: .controlBackgroundColor))
            #endif
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingFullReport) {
            PerformanceReportView(report: report)
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

struct PerformanceReportsListView: View {
    let reports: [PerformanceReport]
    @Environment(\.dismiss) private var dismiss
    
    @State private var reportToDelete: PerformanceReport?
    @State private var isShowingDeleteAlert = false
    
    @Environment(\.modelContext) private var modelContext

    private func deleteReport(_ report: PerformanceReport) {
        modelContext.delete(report)
        try? modelContext.save()
    }
    
    var body: some View {
        NavigationView {
            List {
                if self.reports.isEmpty {
                    ContentUnavailableView(
                        "No Reports Found",
                        systemImage: "xmark.circle",
                        description: Text(
                            "We couldn't find any performance reports. They are automatically generated when a performance is finished."
                        )
                    )
                } else {
                    ForEach(reports.sorted(by: { $0.performanceDate > $1.performanceDate })) { report in
                        NavigationLink(destination: PerformanceReportView(report: report)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(report.performanceDate.formatted(date: .abbreviated, time: .shortened))
                                        .font(.headline)
                                    
                                    Spacer()
                                    
                                    StatusBadge(state: report.currentState)
                                }
                                
                                HStack {
                                    Text("Runtime: \(formatDuration(report.totalRuntime))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Text("\(report.callsExecuted) calls • \(report.cuesExecuted) cues")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if report.showStops > 0 {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.red)
                                        Text("\(report.showStops) show stops")
                                            .foregroundColor(.red)
                                    }
                                    .font(.caption)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                reportToDelete = report
                                isShowingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Performance Reports")
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
            .alert("Delete Report", isPresented: $isShowingDeleteAlert, presenting: reportToDelete) { report in
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteReport(report)
                }
            } message: { report in
                Text("Are you sure you want to delete the report from \(report.performanceDate.formatted(date: .abbreviated, time: .shortened))?")
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

struct PerformanceDateRow: View {
    let performanceDate: PerformanceDate
    let performance: Performance?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(performanceDate.date, style: .date)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(performanceDate.date, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if let performance = performance {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Setup Needed", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
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

struct ScriptSummaryCard: View {
    let script: Script
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(script.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("\(script.lines.count) lines")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        #if os(iOS)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        #endif
        #if os(macOS)
        .background(Color(nsColor: .controlBackgroundColor))
        #endif
        .cornerRadius(8)
    }
}

struct EmptyScriptCard: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: "doc.badge.plus")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                
                Text("Add Script")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
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

struct QuickActionCard: View {
    let title: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        #if os(iOS)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        #endif
        #if os(macOS)
        .background(Color(nsColor: .controlBackgroundColor))
        #endif
        .cornerRadius(8)
    }
}

struct EditShowView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var show: Show

    var body: some View {
        Form {
            Section(header: Text("Show Info")) {
                TextField("Title", text: $show.title)
                TextField("Location", text: $show.locationString)
            }

            if show.script != nil {
                Section(header: Text("Script")) {
                    TextField("Script Name", text: Binding(
                        get: { show.script?.name ?? "" },
                        set: { newValue in show.script?.name = newValue }
                    ))
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Save") {
                        dismiss()
                    }
                    Spacer()
                }
            }
        }
        .navigationTitle("Edit Show")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
    }
}

struct PerformanceDetailView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var performanceDate: Date
    @State private var hasChanges = false

    let performance: Performance

    init(performance: Performance) {
        self.performance = performance
        _performanceDate = State(initialValue: performance.date)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Edit Performance Date")
                    .font(.headline)
                    .padding(.top)
                
                DatePicker("Date & Time", selection: $performanceDate, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)
                    .onChange(of: performanceDate) { _ in
                        hasChanges = true
                    }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Performance")
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
                        performance.date = performanceDate
                        dismiss()
                    }
                    .disabled(!hasChanges)
                }
            }
        }
    }
}

#Preview {
    let sampleShow = Show(
        id: UUID(),
        title: "Hamlet",
        dates: [Date(), Date().addingTimeInterval(86400)],
        locationString: "Royal Shakespeare Theatre",
        script: Script(id: UUID(), name: "Hamlet Script", dateAdded: Date(), lines: []),
        peformances: []
    )
    
    ShowDetailView(show: sampleShow)
}
