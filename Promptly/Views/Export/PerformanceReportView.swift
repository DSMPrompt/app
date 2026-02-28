//
//  PerformanceReportView.swift
//  Promptly
//
//  Created by Sasha Bagrov on 05/06/2025.
//

import Foundation
import SwiftUI
import SwiftData
import PDFKit

struct PerformanceReportView: View {
    let report: PerformanceReport
    @State private var showingShareSheet = false
    @State private var pdfURL: URL?
    @Environment(\.dismiss) private var dismiss
    
    @State private var generatePDFSheetIsPresent = false
    
    var body: some View {
        Group {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    reportHeader
                    
                    performanceOverview
                    
                    timingDetails
                    
                    executionSummary
                    
                    if !report.showStopDetails.isEmpty {
                        showStopsSection
                    }
                    
                    if !report.cueExecutions.isEmpty {
                    cueExecutionsSection
                }
                
                callLogSection
                    
                    notesSection
                }
                .padding()
            }
            .navigationTitle("Performance Report")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("Export PDF", systemImage: "square.and.arrow.up") {
                            generatePDFSheetIsPresent = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $generatePDFSheetIsPresent) {
            if let pdfURL = pdfURL {
                #if os(iOS)
                ShareSheet(items: [pdfURL])
                #else
                VStack {
                    Text("PDF Generated")
                        .font(.headline)
                    Text("Location: \(pdfURL.path)")
                        .font(.caption)
                        .padding()
                    Button("Done") {
                        generatePDFSheetIsPresent = false
                    }
                }
                .padding()
                #endif
            } else {
                ProgressView("Compiling PDF...")
                    .onAppear {
                        generatePDF()
                    }
            }
        }
    }
    
    private var reportHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(report.showTitle)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Performance: \(report.performanceDate.formatted(date: .long, time: .shortened))")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                StatusBadge(state: report.currentState)
                Spacer()
                Text("Generated: \(report.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var performanceOverview: some View {
        ReportSection(title: "Performance Overview") {
            VStack(spacing: 12) {
                OverviewMetric(
                    title: "Total Runtime",
                    value: formatDuration(report.totalRuntime),
                    icon: "clock",
                    color: .blue
                )
                
                OverviewMetric(
                    title: "Calls Executed",
                    value: "\(report.callsExecuted)",
                    icon: "speaker.wave.2",
                    color: .green
                )
                
                OverviewMetric(
                    title: "Cues Executed",
                    value: "\(report.cuesExecuted)",
                    icon: "lightbulb",
                    color: .orange
                )
                
                if report.showStops > 0 {
                    OverviewMetric(
                        title: "Show Stops",
                        value: "\(report.showStops)",
                        icon: "exclamationmark.triangle",
                        color: .red
                    )
                }
            }
        }
    }
    
    private var timingDetails: some View {
        ReportSection(title: "Timing Details") {
            VStack(alignment: .leading, spacing: 8) {
                if let startTime = report.startTime {
                    TimingRow(label: "Started", time: startTime)
                }
                
                if let endTime = report.endTime {
                    TimingRow(label: "Ended", time: endTime)
                }
                
                if let startTime = report.startTime, let endTime = report.endTime {
                    HStack {
                        Text("Total Duration:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(formatDuration(endTime.timeIntervalSince(startTime)))
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
    
    private var executionSummary: some View {
        ReportSection(title: "Execution Summary") {
            VStack(alignment: .leading, spacing: 8) {
                SummaryRow(label: "Total Calls", value: "\(report.callsExecuted)")
                SummaryRow(label: "Manual Cue Executions", value: "\(report.cuesExecuted)")
                SummaryRow(label: "Remote Control Usage", value: "\(report.callLogEntries.filter { $0.message.contains("REMOTE") }.count)")
                
                if report.emergencyStops > 0 {
                    SummaryRow(label: "Emergency Stops", value: "\(report.emergencyStops)", color: .red)
                }
            }
        }
    }
    
    private var showStopsSection: some View {
        ReportSection(title: "Show Stops") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(report.showStopDetails) { stop in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Act \(stop.actNumber)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.2))
                                .cornerRadius(4)
                            
                            Text(stop.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if stop.duration > 0 {
                                Text(formatDuration(stop.duration))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                            }
                        }
                        
                        Text(stop.reason)
                            .font(.subheadline)
                            .padding(.leading, 4)
                    }
                    .padding(.vertical, 4)
                    
                    if stop != report.showStopDetails.last {
                        Divider()
                    }
                }
            }
        }
    }
    
    private var cueExecutionsSection: some View {
        ReportSection(title: "Cue Executions (\(report.cueExecutions.count) cues)") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(report.cueExecutions.sorted(by: { $0.timestamp < $1.timestamp })) { execution in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Line \(execution.lineNumber)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                            
                            Text(execution.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                            
                            Spacer()
                            
                            Text(execution.executionMethod)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(execution.executionMethod == "Remote Control" ? Color.purple.opacity(0.2) : Color.green.opacity(0.2))
                                .cornerRadius(4)
                        }
                        
                        HStack {
                            Text(execution.cueLabel)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text(execution.cueType)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if execution != report.cueExecutions.last {
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }
    
    private var callLogSection: some View {
        ReportSection(title: "Complete Call Log (\(report.callLogEntries.count) entries)") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(report.callLogEntries.reversed().enumerated()), id: \.offset) { index, entry in
                    HStack {
                        Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                            .frame(width: 80, alignment: .leading)
                        
                        Text(entry.message)
                            .font(.caption)
                            .lineLimit(3)
                        
                        Spacer()
                        
                        Circle()
                            .fill(colorForCallType(entry.type))
                            .frame(width: 6, height: 6)
                    }
                    .padding(.vertical, 2)
                    
                    if index < report.callLogEntries.count - 1 {
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 400)
        }
    }
    
    private var notesSection: some View {
        ReportSection(title: "Notes") {
            VStack(alignment: .leading, spacing: 8) {
                if report.notes.isEmpty {
                    Text("No additional notes recorded.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    Text(report.notes)
                        .font(.subheadline)
                }
            }
        }
    }

    #if os(iOS)
    private func generatePDF() {
        print("🔄 Starting PDF generation...")
        let pdfGenerator = PerformanceReportPDFGenerator()

        DispatchQueue.global(qos: .userInitiated).async {
            if let url = pdfGenerator.generatePDF(for: report) {
                DispatchQueue.main.async {
                    print("✅ PDF generated at: \(url)")
                    self.pdfURL = url
                }
            } else {
                print("❌ Failed to generate PDF")
            }
        }
    }
    #else
    private func generatePDF() {
        print("⚠️ PDF generation not available on macOS")
    }
    #endif
    
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
    
    private func colorForCallType(_ type: String) -> Color {
        switch type {
        case "call": return .blue
        case "action": return .green
        case "emergency": return .red
        case "note": return .orange
        default: return .gray
        }
    }
}

struct ReportSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
            
            content
                .padding()
                #if os(iOS)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                #endif
                #if os(macOS)
                .background(Color(nsColor: .controlBackgroundColor))
                #endif
                .cornerRadius(12)
        }
    }
}

struct StatusBadge: View {
    let state: PerformanceState
    
    var body: some View {
        Text(state.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(state.color)
            .cornerRadius(8)
    }
}

struct OverviewMetric: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Spacer()
        }
    }
}

struct TimingRow: View {
    let label: String
    let time: Date
    
    var body: some View {
        HStack {
            Text(label + ":")
                .fontWeight(.medium)
            Spacer()
            Text(time.formatted(date: .omitted, time: .standard))
                .monospacedDigit()
        }
    }
}

struct SummaryRow: View {
    let label: String
    let value: String
    let color: Color?
    
    init(label: String, value: String, color: Color? = nil) {
        self.label = label
        self.value = value
        self.color = color
    }
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color ?? .primary)
        }
    }
}

#if os(iOS)
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

class PerformanceReportPDFGenerator {
    func generatePDF(for report: PerformanceReport) -> URL? {
        print("📄 Generating PDF for report: \(report.showTitle)")
        
        let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let safeTitle = report.showTitle.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "-")
        let fileName = "PerformanceReport_\(safeTitle)_\(report.performanceDate.formatted(date: .abbreviated, time: .omitted)).pdf"
        let pdfURL = documentsPath.appendingPathComponent(fileName)
        
        print("📁 PDF will be saved to: \(pdfURL)")
        
        do {
            try pdfRenderer.writePDF(to: pdfURL) { context in
                print("✏️ Writing PDF content...")
                context.beginPage()
                
                var yPosition: CGFloat = 50
                
                yPosition = drawTitle(report.showTitle, at: yPosition, in: context.cgContext)
                yPosition = drawSubtitle("Performance Report", at: yPosition, in: context.cgContext)
                yPosition = drawText("Date: \(report.performanceDate.formatted(date: .long, time: .shortened))", at: yPosition, in: context.cgContext)
                yPosition += 20
                
                yPosition = drawSectionHeader("Performance Overview", at: yPosition, in: context.cgContext)
                yPosition = drawText("Runtime: \(formatDuration(report.totalRuntime))", at: yPosition, in: context.cgContext)
                yPosition = drawText("Calls Executed: \(report.callsExecuted)", at: yPosition, in: context.cgContext)
                yPosition = drawText("Cues Executed: \(report.cuesExecuted)", at: yPosition, in: context.cgContext)
                yPosition = drawText("Show Stops: \(report.showStops)", at: yPosition, in: context.cgContext)
                
                if report.showStops > 0 {
                    for entry in report.callLogEntries {
                        if entry.message.contains("EMERGENCY STOP: ") {
                            if let range = entry.message.range(of: "EMERGENCY STOP: ") {
                                let textAfterStop = String(entry.message[range.upperBound...])
                                yPosition = drawText("  E STOP: \(textAfterStop)", at: yPosition, in: context.cgContext)
                            }
                        }
                    }
                }
                yPosition += 20
                
                if let startTime = report.startTime, let endTime = report.endTime {
                    yPosition = drawSectionHeader("Timing Details", at: yPosition, in: context.cgContext)
                    yPosition = drawText("Started: \(startTime.formatted(date: .omitted, time: .standard))", at: yPosition, in: context.cgContext)
                    yPosition = drawText("Ended: \(endTime.formatted(date: .omitted, time: .standard))", at: yPosition, in: context.cgContext)
                    yPosition += 20
                }
                
                yPosition = drawSectionHeader("Cue Executions", at: yPosition, in: context.cgContext)
                for execution in report.cueExecutions.prefix(15) {
                    let text = "Line \(execution.lineNumber): \(execution.cueLabel) (\(execution.cueType)) - \(execution.executionMethod) at \(execution.timestamp.formatted(date: .omitted, time: .standard))"
                    yPosition = drawText(text, at: yPosition, in: context.cgContext, fontSize: 10)
                    
                    if yPosition > 700 {
                        context.beginPage()
                        yPosition = 50
                    }
                }
                yPosition += 20
                
                yPosition = drawSectionHeader("Call Log (Last 15 entries)", at: yPosition, in: context.cgContext)
                for entry in report.callLogEntries.suffix(15).reversed() {
                    let text = "\(entry.timestamp.formatted(date: .omitted, time: .standard)) - \(entry.message)"
                    yPosition = drawText(text, at: yPosition, in: context.cgContext, fontSize: 10)
                    
                    if yPosition > 700 {
                        context.beginPage()
                        yPosition = 50
                    }
                }
            }
            
            print("✅ PDF generated successfully!")
            return pdfURL
        } catch {
            print("❌ Failed to generate PDF: \(error)")
            return nil
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
    
    private func drawTitle(_ text: String, at y: CGFloat, in context: CGContext) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 24),
            .foregroundColor: UIColor.black
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        attributedString.draw(at: CGPoint(x: 50, y: y))
        return y + textSize.height + 10
    }
    
    private func drawSubtitle(_ text: String, at y: CGFloat, in context: CGContext) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: UIColor.blue
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        attributedString.draw(at: CGPoint(x: 50, y: y))
        return y + textSize.height + 5
    }
    
    private func drawSectionHeader(_ text: String, at y: CGFloat, in context: CGContext) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 16),
            .foregroundColor: UIColor.black
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        attributedString.draw(at: CGPoint(x: 50, y: y))
        return y + textSize.height + 8
    }
    
    private func drawText(_ text: String, at y: CGFloat, in context: CGContext, fontSize: CGFloat = 12) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize),
            .foregroundColor: UIColor.black
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        attributedString.draw(at: CGPoint(x: 50, y: y))
        return y + textSize.height + 4
    }
}
#endif
