import SwiftUI
import SwiftData

struct DSMPerformanceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let performance: Performance
    @State private var performanceTiming: PerformanceTiming
    @State private var currentState: PerformanceState = .preShow
    @State private var isShowRunning = false
    @State private var showingEndConfirmation = false
    @State private var showingStopAlert = false
    @State private var stopReason = ""
    @State private var callsLog: [CallLogEntry] = []
    @State private var currentLineNumber = 1
    @State private var allCues: [Cue] = []
    @State private var calledCues: Set<UUID> = []
    @State private var hiddenCues: Set<UUID> = []
    @State private var cueHideTimers: [UUID: Timer] = [:]
    @State private var showingDetails = false
    @State private var showingSettings = false
    @State private var showingBluetoothSettings = false
    @State private var keepDisplayAwake = true
    @State private var scrollToChangesActiveLine = false
    @State private var currentTime = Date()
    @State private var stopTime: Date?
    @State private var cueExecutions: [ReportCueExecution] = []
    @State private var showingCueAlert = false
    @State private var cueAlertTimer: Timer?
    @FocusState private var isViewFocused: Bool
    @StateObject private var bluetoothManager = PromptlyBluetoothManager()
    @StateObject private var mqttManager = MQTTManager()

    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var script: Script? {
        performance.show?.script
    }
    
    // private var sortedLinesCache: [ScriptLine] {
    //     script?.lines.sorted { $0.lineNumber < $1.lineNumber } ?? []
    // }
    
    @State private var sortedLinesCache: [ScriptLine] = []
    
    @State private var sortedCuesCache: [Cue] = []

    private func updateCuesCache() {
        let lineMap = Dictionary(uniqueKeysWithValues: sortedLinesCache.map { ($0.id, $0) })
        sortedCuesCache = allCues
            .filter { !hiddenCues.contains($0.id) }
            .sorted {
                guard let lhsLine = lineMap[$0.lineId], let rhsLine = lineMap[$1.lineId] else { return false }
                if lhsLine.lineNumber == rhsLine.lineNumber {
                    return $0.position.elementIndex < $1.position.elementIndex
                }
                return lhsLine.lineNumber < rhsLine.lineNumber
            }
    }
    
    private var sortedSections: [ScriptSection] {
        script?.sections.sorted { $0.startLineNumber < $1.startLineNumber } ?? []
    }
    
    private var sortedAllCues: [Cue] {
        allCues.filter { !hiddenCues.contains($0.id) }.sorted { lhs, rhs in
            guard let lhsLine = sortedLinesCache.first(where: { $0.id == lhs.lineId }),
                  let rhsLine = sortedLinesCache.first(where: { $0.id == rhs.lineId }) else {
                return false
            }
            if lhsLine.lineNumber == rhsLine.lineNumber {
                return lhs.position.elementIndex < rhs.position.elementIndex
            }
            return lhsLine.lineNumber < rhsLine.lineNumber
        }
    }
    
    private var currentRuntime: TimeInterval {
        guard let startTime = performanceTiming.startTime else { return 0 }
        let endPoint = stopTime ?? currentTime
        return endPoint.timeIntervalSince(startTime)
    }
    
    private var canMakeQuickCalls: Bool {
        switch currentState {
        case .preShow, .houseOpen, .clearance:
            return true
        default:
            return isShowRunning
        }
    }
    
    private func updateLinesCache() {
        sortedLinesCache = script?.lines.sorted { $0.lineNumber < $1.lineNumber } ?? []
    }
    
    init(performance: Performance) {
        self.performance = performance
        
        if let existingTiming = performance.timing {
            self._performanceTiming = State(initialValue: existingTiming)
            self._currentState = State(initialValue: existingTiming.currentState)
        } else {
            let newTiming = PerformanceTiming(
                curtainTime: performance.date,
                houseOpenPlanned: performance.date.addingTimeInterval(-30 * 60),
                acts: [],
                intervals: [],
                callSettings: CallSettings(),
                currentState: .preShow,
                actTimings: [],
                showStops: []
            )
            self._performanceTiming = State(initialValue: newTiming)
            self._currentState = State(initialValue: .preShow)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    compactHeader

                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            scriptHeaderBar
                            scriptContentView
                                .frame(maxHeight: .infinity)
                        }
                        .frame(width: geometry.size.width * 0.7)
                        .frame(maxHeight: .infinity)
                        .background(Color(.systemBackground))

                        VStack(spacing: 0) {
                            cuesPanelHeader
                            cuesContentView
                        }
                        .frame(width: geometry.size.width * 0.3)
                        .frame(maxHeight: .infinity)
                        .background(Color(.secondarySystemBackground))
                    }
                }

                if showingCueAlert {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.red)
                                .frame(width: 30, height: 30)
                                .opacity(showingCueAlert ? 1.0 : 0.0)
                                .animation(.easeInOut(duration: 0.2).repeatCount(10, autoreverses: true), value: showingCueAlert)
                                .padding(.trailing, 20)
                                .padding(.bottom, 20)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .focusable()
        .focused($isViewFocused)
        .onKeyPress(.downArrow) {
            withAnimation(.easeOut(duration: 0.1)) {
                moveToLine(currentLineNumber + 1)
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            withAnimation(.easeOut(duration: 0.1)) {
                moveToLine(currentLineNumber - 1)
            }
            return .handled
        }
        .onAppear {
            isViewFocused = true
            if keepDisplayAwake {
                UIApplication.shared.isIdleTimerDisabled = true
            }

            sortedLinesCache = script?.lines.sorted { $0.lineNumber < $1.lineNumber } ?? []
            updateLinesCache()
            loadAllCues()
            updateCuesCache()
            
            mqttManager.connect(to: "192.168.1.185", port: 1883)
            
            bluetoothManager.onButtonPress = { value in
                if value == "1" {
                    withAnimation(.easeOut(duration: 0.1)) {
                        moveToLine(currentLineNumber + 1)
                    }
                } else if value == "0" {
                    withAnimation(.easeOut(duration: 0.1)) {
                        moveToLine(currentLineNumber - 1)
                    }
                } else if value == "2" {
                    executeNextCue()
                }
            }
        }
        .onChange(of: allCues) { _, _ in updateCuesCache() }
        .onChange(of: hiddenCues) { _, _ in updateCuesCache() }
        .onChange(of: sortedLinesCache) { _, _ in updateCuesCache() }
        .onChange(of: script) { _, _ in
            updateLinesCache()
            loadAllCues()
            updateCuesCache()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            for timer in cueHideTimers.values {
                timer.invalidate()
            }
            cueHideTimers.removeAll()
            cueAlertTimer?.invalidate()
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
        .alert("Emergency Stop", isPresented: $showingStopAlert) {
            TextField("Reason", text: $stopReason)
            Button("Cancel", role: .cancel) { }
            Button("Stop Show", role: .destructive) {
                emergencyStop()
            }
        }
        .alert("End Performance", isPresented: $showingEndConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("End Show") {
                endPerformance()
            }
        }
        .sheet(isPresented: $showingBluetoothSettings) {
            PromptlyBluetoothSettingsView(bluetoothManager: bluetoothManager)
        }
        .sheet(isPresented: $showingSettings) {
            DSMSettingsView(
                keepDisplayAwake: $keepDisplayAwake,
                scrollToChangesActiveLine: $scrollToChangesActiveLine
            )
        }
        .sheet(isPresented: $showingDetails) {
            DSMDetailsView(
                performance: performance,
                timing: $performanceTiming,
                callsLog: $callsLog,
                currentState: $currentState,
                isShowRunning: $isShowRunning,
                canMakeQuickCalls: canMakeQuickCalls,
                onStartShow: { startShow() },
                onStopShow: { showingStopAlert = true },
                onEndShow: { showingEndConfirmation = true },
                onStartInterval: { startInterval() },
                onStartNextAct: { startNextAct() }
            )
        }
    }
    
    private var compactHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(performance.show?.title ?? "Performance")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Text(currentState.displayName)
                        .font(.caption)
                        .foregroundColor(currentState.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(currentState.color.opacity(0.2))
                        .cornerRadius(4)
                    
                    if case .preShow = currentState {
                        Button("House Open") {
                            currentState = .houseOpen
                            performanceTiming.houseOpenTime = Date()
                            performanceTiming.currentState = .houseOpen
                            logCall("House Open", type: .action)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                    }
                    
                    if case .houseOpen = currentState {
                        Button("Clearance") {
                            currentState = .clearance
                            performanceTiming.clearanceTime = Date()
                            performanceTiming.currentState = .clearance
                            logCall("Stage Clear - Beginners", type: .call)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(currentTime.formatted(date: .omitted, time: .standard))
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(.primary)
                
                if performanceTiming.startTime != nil {
                    Text("Runtime: \(formatTimeInterval(currentRuntime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
            
            HStack(spacing: 8) {
                Button(action: {
                    showingBluetoothSettings = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: bluetoothManager.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                            .foregroundColor(bluetoothManager.isConnected ? .blue : .secondary)
                        if bluetoothManager.isConnected {
                            Text("Remote")
                                .font(.caption)
                        }
                    }
                }
                .buttonStyle(.bordered)
                
                Button("Settings") {
                    showingSettings = true
                }
                .buttonStyle(.bordered)
                
                Button("Details") {
                    showingDetails = true
                }
                .buttonStyle(.bordered)
                
                if isShowRunning {
                    Button("STOP", role: .destructive) {
                        showingStopAlert = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button("START") {
                        startShow()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(currentState == .preShow || currentState == .houseOpen)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .overlay(alignment: .bottom) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator))
        }
    }
    
    private var scriptHeaderBar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("SCRIPT")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Text("Line \(currentLineNumber)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 8) {
                        Button("Go to Line") {
                            
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray4))
                        .cornerRadius(4)
                        
                        HStack(spacing: 4) {
                            Button(action: { moveToLine(currentLineNumber - 1) }) {
                                Image(systemName: "chevron.up")
                                    .font(.caption)
                            }
                            .disabled(currentLineNumber <= 1)
                            
                            Button(action: { moveToLine(currentLineNumber + 1) }) {
                                Image(systemName: "chevron.down")
                                    .font(.caption)
                            }
                            .disabled(currentLineNumber >= sortedLinesCache.count)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            
            let currentSection = sectionsForCurrentLine()
            if let section = currentSection {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(hex: section.type.color))
                        .frame(width: 2, height: 8)
                    
                    Text(section.title)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("L\(section.startLineNumber)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 2)
                .background(Color(hex: section.type.color).opacity(0.05))
            }
            
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator))
        }
    }
    
    private var cuesPanelHeader: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ALL CUES")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(allCues.count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGray5))
            
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separator))
        }
    }
    
    // private var scriptContentView: some View {
    //     ScrollViewReader { proxy in
    //         ScrollView {
    //             LazyVStack(alignment: .leading, spacing: 8) {
    //                 ForEach(groupLinesBySection(), id: \.stableId) { group in
    //                     if let section = group.section {
    //                         DSMSectionHeaderView(section: section)
    //                             .id("section-\(section.id)")
    //                     }
    //
    //                     // ForEach(group.lines, id: \.id) { line in
    //                     //     DSMScriptLineView(
    //                     //         line: line,
    //                     //         isCurrent: line.lineNumber == currentLineNumber,
    //                     //         onLineTap: {
    //                     //             currentLineNumber = line.lineNumber
    //                     //         },
    //                     //         calledCues: calledCues
    //                     //     )
    //                     //     .id("line-\(line.lineNumber)")
    //                     // }
    //
    //                     // ForEach(group.lines, id: \.id) { line in
    //                     //     if abs(line.lineNumber - currentLineNumber) < 50 {
    //                     //         DSMScriptLineView(
    //                     //             line: line,
    //                     //             isCurrent: line.lineNumber == currentLineNumber,
    //                     //             onLineTap: {
    //                     //                 currentLineNumber = line.lineNumber
    //                     //             },
    //                     //             calledCues: calledCues
    //                     //         )
    //                     //     }
    //                     // }
    //
    //                     ForEach(group.lines.prefix(500), id: \.id) { line in
    //                         Text("L\(line.lineNumber): \(line.content)")
    //                             .padding(.vertical, 4)
    //                             .id("line-\(line.lineNumber)")
    //                     }
    //                 }
    //             }
    //             .padding()
    //         }
    //         .onChange(of: currentLineNumber) { _, newValue in
    //             withAnimation(.easeOut(duration: 0.15)) {
    //                 proxy.scrollTo("line-\(newValue)", anchor: .center)
    //             }
    //         }
    //     }
    // }
    
    // private var scriptContentView: some View {
    //     ScrollViewReader { proxy in
    //         ScrollView {
    //             LazyVStack(alignment: .leading, spacing: 8) {
    //                 ForEach(sortedLinesCache.prefix(300), id: \.id) { line in
    //                     Text("L\(line.lineNumber): \(line.content)")
    //                         .padding(.vertical, 4)
    //                         .id("line-\(line.lineNumber)")
    //                 }
    //             }
    //             .padding()
    //         }
    //         .onChange(of: currentLineNumber) { _, newValue in
    //             proxy.scrollTo("line-\(newValue)", anchor: .center)
    //         }
    //     }
    // }
    
    private var scriptContentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(sortedLinesCache, id: \.id) { line in
                        DSMScriptLineView(
                            line: line,
                            isCurrent: line.lineNumber == currentLineNumber,
                            onLineTap: {
                                currentLineNumber = line.lineNumber
                                self.mqttManager.sendData(to: "shows/1/line", message: "\(line.lineNumber)")
                            },
                            calledCues: calledCues
                        )
                        .id("line-\(line.lineNumber)")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(.systemBackground)) // improves gesture hitbox
            .onChange(of: currentLineNumber) { _, newValue in
                proxy.scrollTo("line-\(newValue)", anchor: .center)
            }
        }
    }
    
    private var cuesContentView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if sortedCuesCache.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                            .font(.title)
                            .foregroundColor(.secondary)
                        
                        Text("No Cues")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Text("Cues will appear here as you navigate the script")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 40)
                } else {
                    ForEach(sortedCuesCache) { cue in
                        DSMCueBoxView(
                            cue: cue,
                            isCalled: calledCues.contains(cue.id)
                        ) {
                            scrollToCue(cue)
                        } onExecute: {
                            executeCue(cue)
                        } onToggleCalled: {
                            toggleCueCalled(cue)
                        }
                    }
                }
            }
            .padding()
        }
        .frame(maxHeight: .infinity)
    }
    
    private struct LineGroup {
        let section: ScriptSection?
        let lines: [ScriptLine]
        
        var stableId: String {
            if let section = section {
                return "section-\(section.id)"
            } else {
                let lineIds = lines.map { $0.id.uuidString }.joined(separator: "-")
                return "unsectioned-\(lineIds.hashValue)"
            }
        }
    }
    
    private func groupLinesBySection() -> [LineGroup] {
        let currentSortedLines = sortedLinesCache
        let currentSortedSections = sortedSections
        
        var groups: [LineGroup] = []
        var lineIndex = 0
        var sectionIndex = 0
        
        while lineIndex < currentSortedLines.count {
            let currentLine = currentSortedLines[lineIndex]
            
            if sectionIndex < currentSortedSections.count &&
               currentLine.lineNumber >= currentSortedSections[sectionIndex].startLineNumber {
                
                let section = currentSortedSections[sectionIndex]
                var sectionLines: [ScriptLine] = []
                
                let sectionEnd: Int
                if let explicitEnd = section.endLineNumber {
                    sectionEnd = explicitEnd
                } else if sectionIndex + 1 < currentSortedSections.count {
                    sectionEnd = currentSortedSections[sectionIndex + 1].startLineNumber - 1
                } else {
                    sectionEnd = Int.max
                }
                
                while lineIndex < currentSortedLines.count &&
                      currentSortedLines[lineIndex].lineNumber >= section.startLineNumber &&
                      currentSortedLines[lineIndex].lineNumber <= sectionEnd {
                    sectionLines.append(currentSortedLines[lineIndex])
                    lineIndex += 1
                }
                
                if !sectionLines.isEmpty {
                    groups.append(LineGroup(section: section, lines: sectionLines))
                }
                
                sectionIndex += 1
            } else {
                var unsectionedGroup: [ScriptLine] = []
                
                while lineIndex < currentSortedLines.count {
                    let line = currentSortedLines[lineIndex]
                    
                    if sectionIndex < currentSortedSections.count &&
                       line.lineNumber >= currentSortedSections[sectionIndex].startLineNumber {
                        break
                    }
                    
                    unsectionedGroup.append(line)
                    lineIndex += 1
                }
                
                if !unsectionedGroup.isEmpty {
                    groups.append(LineGroup(section: nil, lines: unsectionedGroup))
                }
            }
        }
        
        return groups
    }
    
    private func sectionsForCurrentLine() -> ScriptSection? {
        return sortedSections
            .filter { section in
                let isAfterStart = currentLineNumber >= section.startLineNumber
                let isBeforeEnd = section.endLineNumber == nil || currentLineNumber <= (section.endLineNumber ?? Int.max)
                return isAfterStart && isBeforeEnd
            }
            .max(by: { $0.startLineNumber < $1.startLineNumber })
    }
    
    private func showCueAlert() {
        showingCueAlert = true
        
        cueAlertTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            showingCueAlert = false
            cueAlertTimer = nil
        }
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = Int(interval) % 3600 / 60
        let seconds = Int(interval) % 60
        
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

struct DSMSectionHeaderView: View {
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

struct DSMSectionBadge: View {
    let section: ScriptSection
    
    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: section.type.color))
                .frame(width: 3, height: 16)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(section.type.displayName.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text(section.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            
            Text("L\(section.startLineNumber)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color(.tertiarySystemFill))
                .cornerRadius(3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: section.type.color).opacity(0.1))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(hex: section.type.color).opacity(0.3), lineWidth: 0.5)
        )
    }
}

struct DSMScriptLineView: View {
    let line: ScriptLine
    let isCurrent: Bool
    let onLineTap: () -> Void
    let calledCues: Set<UUID>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onLineTap) {
                HStack(alignment: .top, spacing: 12) {
                    Text("\(line.lineNumber)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(isCurrent ? .black : .secondary)
                        .frame(width: 30, alignment: .trailing)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        scriptLineWithCues
                        scriptContentWithCueArrows
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isCurrent ? Color.yellow : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isCurrent ? Color.orange : Color.clear, lineWidth: 2)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var scriptLineWithCues: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !line.cues.isEmpty {
                HStack(spacing: 4) {
                    ForEach(line.cues) { cue in
                        CueTagView(cue: cue, isCalled: calledCues.contains(cue.id))
                    }
                    Spacer()
                }
            }
        }
    }
    
    private var scriptContentWithCueArrows: some View {
        let cuesByIndex = Dictionary(grouping: line.cues) { $0.position.elementIndex }
        let words = line.content.split(separator: " ", omittingEmptySubsequences: false)
        
        return Text(buildLineWithCues(words: words, cuesByIndex: cuesByIndex))
            .font(.body)
            .foregroundColor(isCurrent ? .black : .primary)
    }

    private func buildLineWithCues(words: [Substring], cuesByIndex: [Int: [Cue]]) -> AttributedString {
        var result = AttributedString()
        
        for (i, word) in words.enumerated() {
            if let cues = cuesByIndex[i] {
                for cue in cues {
                    var label = AttributedString("⬇︎ \(cue.label) ")

                    label.foregroundColor = calledCues.contains(cue.id) ? .secondary : Color(hex: cue.type.categoryColor)
                    label.inlinePresentationIntent = .emphasized

                    if calledCues.contains(cue.id) {
                        label.strikethroughStyle = Text.LineStyle.single
                    }
                    result += label
                }
            }
            
            var wordAttr = AttributedString(word + " ")
            result += wordAttr
        }
        
        return result
    }
}

struct DSMFlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = DSMFlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = DSMFlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX, y: bounds.minY + result.frames[index].minY), proposal: .unspecified)
        }
    }
}

struct DSMFlowResult {
    var frames: [CGRect] = []
    var size: CGSize = .zero
    
    init(in maxWidth: CGFloat, subviews: LayoutSubviews, spacing: CGFloat) {
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
            
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        
        self.size = CGSize(width: maxWidth, height: currentY + lineHeight)
    }
}

struct CueTagView: View {
    let cue: Cue
    let isCalled: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: cue.type.categoryColor))
                .frame(width: 8, height: 8)
            
            Text(cue.label)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)
                .foregroundColor(isCalled ? .secondary : .primary)
                .strikethrough(isCalled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: cue.type.categoryColor).opacity(isCalled ? 0.1 : 0.2))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isCalled ? Color.gray : Color(hex: cue.type.categoryColor), lineWidth: 2)
        )
    }
}

struct DSMSettingsView: View {
    @Binding var keepDisplayAwake: Bool
    @Binding var scrollToChangesActiveLine: Bool
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Display") {
                    Toggle("Keep Display Awake", isOn: $keepDisplayAwake)
                        .onChange(of: keepDisplayAwake) { _, newValue in
                            UIApplication.shared.isIdleTimerDisabled = newValue
                        }
                }
                
                Section("Navigation") {
                    Toggle("Scroll to Cue Changes Active Line", isOn: $scrollToChangesActiveLine)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Keep Display Awake: When enabled, the display will not automatically turn off during the performance.")
                        
                        Text("Scroll to Cue Changes Active Line: When enabled, using 'Scroll to' on a cue will make that line the active line. When disabled, it will only scroll to show the line without changing selection.")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } header: {
                    Text("About Settings")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DSMCueBoxView: View {
    let cue: Cue
    let isCalled: Bool
    let onScroll: () -> Void
    let onExecute: () -> Void
    let onToggleCalled: () -> Void
    
    var body: some View {
        Button(action: onToggleCalled) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Circle()
                        .fill(Color(hex: cue.type.categoryColor))
                        .frame(width: 10, height: 10)
                    
                    Text(cue.label)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(isCalled ? .secondary : .primary)
                        .strikethrough(isCalled)
                    
                    Spacer()
                    
                    if isCalled {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title3)
                    }
                }
                
                Text(cue.type.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if !cue.notes.isEmpty {
                    Text(cue.notes)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                
                HStack(spacing: 8) {
                    Button("Scroll to") {
                        onScroll()
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray4))
                    .cornerRadius(4)
                    
                    Spacer()
                    
                    Button(cue.type.cueTypeDisplay) {
                        onExecute()
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isCalled ? Color.gray : (cue.type.sideColor))
                    .cornerRadius(6)
                    .disabled(isCalled)
                }
            }
            .padding()
            .background(isCalled ? Color(.systemGray6) : Color(.systemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCalled ? Color.gray : Color(hex: cue.type.categoryColor), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DSMDetailsView: View {
    let performance: Performance
    @Binding var timing: PerformanceTiming
    @Binding var callsLog: [CallLogEntry]
    @Binding var currentState: PerformanceState
    @Binding var isShowRunning: Bool
    let canMakeQuickCalls: Bool
    let onStartShow: () -> Void
    let onStopShow: () -> Void
    let onEndShow: () -> Void
    let onStartInterval: () -> Void
    let onStartNextAct: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var currentTime = Date()
    @State private var stopTime: Date?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Text("Current State")
                            .font(.headline)
                        
                        HStack {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(currentState.color)
                                .frame(width: 6, height: 30)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(currentState.displayName)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                if let startTime = timing.startTime {
                                    let runtime = stopTime ?? currentTime
                                    Text("Runtime: \(timeInterval(from: startTime, to: runtime))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(currentState.color.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    VStack(spacing: 16) {
                        Text("Performance Controls")
                            .font(.headline)
                        
                        if !isShowRunning {
                            VStack(spacing: 12) {
                                if case .preShow = currentState {
                                    DSMActionButton(
                                        title: "House Open",
                                        subtitle: "Open to audience",
                                        icon: "door.left.hand.open",
                                        color: .blue
                                    ) {
                                        currentState = .houseOpen
                                        timing.houseOpenTime = Date()
                                        timing.currentState = .houseOpen
                                        logCall("House Open", type: .action)
                                    }
                                }
                                
                                if case .houseOpen = currentState {
                                    DSMActionButton(
                                        title: "Clearance",
                                        subtitle: "Stage clear - Beginners",
                                        icon: "checkmark.shield",
                                        color: .orange
                                    ) {
                                        currentState = .clearance
                                        timing.clearanceTime = Date()
                                        timing.currentState = .clearance
                                        logCall("Stage Clear - Beginners", type: .call)
                                    }
                                }
                                
                                if case .clearance = currentState {
                                    DSMActionButton(
                                        title: "Start Show",
                                        subtitle: "Begin Act 1",
                                        icon: "play.fill",
                                        color: .green
                                    ) {
                                        onStartShow()
                                        dismiss()
                                    }
                                }
                            }
                        } else {
                            if case .inProgress(let actNumber) = currentState {
                                VStack(spacing: 12) {
                                    Text("Act \(actNumber) Running")
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    HStack(spacing: 16) {
                                        DSMActionButton(
                                            title: "Stop Show",
                                            subtitle: "Emergency stop",
                                            icon: "stop.fill",
                                            color: .red
                                        ) {
                                            onStopShow()
                                            dismiss()
                                        }
                                        
                                        if actNumber == 1 {
                                            DSMActionButton(
                                                title: "Start Interval",
                                                subtitle: "End Act 1",
                                                icon: "pause.rectangle",
                                                color: .blue
                                            ) {
                                                onStartInterval()
                                                dismiss()
                                            }
                                        } else {
                                            DSMActionButton(
                                                title: "End Show",
                                                subtitle: "Performance complete",
                                                icon: "checkmark.circle.fill",
                                                color: .blue
                                            ) {
                                                onEndShow()
                                                dismiss()
                                            }
                                        }
                                    }
                                }
                            }
                            
                            if case .interval(_) = currentState {
                                DSMActionButton(
                                    title: "Start Act 2",
                                    subtitle: "Begin next act",
                                    icon: "play.fill",
                                    color: .green
                                ) {
                                    onStartNextAct()
                                    dismiss()
                                }
                            }
                        }
                    }
                    
                    if canMakeQuickCalls {
                        VStack(spacing: 16) {
                            Text("Quick Calls")
                                .font(.headline)
                            
                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 12) {
                                DSMCallButton(title: "Half Hour", time: "35 min") {
                                    logCall("Half Hour Call", type: .call)
                                }
                                DSMCallButton(title: "Quarter Hour", time: "20 min") {
                                    logCall("Quarter Hour Call", type: .call)
                                }
                                DSMCallButton(title: "Five Minutes", time: "10 min") {
                                    logCall("Five Minutes Call", type: .call)
                                }
                                DSMCallButton(title: "Beginners", time: "5 min") {
                                    logCall("Beginners Call", type: .call)
                                }
                            }
                        }
                    }
                    
                    if timing.startTime != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Performance Statistics")
                                .font(.headline)
                            
                            VStack(spacing: 8) {
                                if let startTime = timing.startTime {
                                    HStack {
                                        Text("Started:")
                                        Spacer()
                                        Text(startTime.formatted(date: .omitted, time: .standard))
                                            .monospacedDigit()
                                    }
                                }
                                
                                if let endTime = timing.endTime {
                                    HStack {
                                        Text("Ended:")
                                        Spacer()
                                        Text(endTime.formatted(date: .omitted, time: .standard))
                                            .monospacedDigit()
                                    }
                                }
                                
                                HStack {
                                    Text("Show Stops:")
                                    Spacer()
                                    Text("\(timing.showStops.count)")
                                }
                                
                                HStack {
                                    Text("Total Calls:")
                                    Spacer()
                                    Text("\(callsLog.count)")
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Call Log")
                            .font(.headline)
                        
                        if callsLog.isEmpty {
                            Text("No calls logged yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(callsLog.suffix(10).reversed()) { entry in
                                    DSMCallLogRow(entry: entry)
                                }
                            }
                            
                            if callsLog.count > 10 {
                                Text("Showing last 10 calls")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Performance Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }
    
    private func timeInterval(from startDate: Date, to endDate: Date) -> String {
        let interval = endDate.timeIntervalSince(startDate)
        let hours = Int(interval) / 3600
        let minutes = Int(interval) % 3600 / 60
        let seconds = Int(interval) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
    
    private func logCall(_ message: String, type: CallLogEntry.CallType = .note) {
        let entry = CallLogEntry(timestamp: Date(), message: message, type: type)
        callsLog.append(entry)
    }
}

struct DSMActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                VStack(spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DSMCallButton: View {
    let title: String
    let time: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.blue, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DSMCallLogRow: View {
    let entry: CallLogEntry
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.subheadline)
                
                Text(entry.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Circle()
                .fill(entry.type.color)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

extension DSMPerformanceView {
    private func startShow() {
        currentState = .inProgress(actNumber: 1)
        performanceTiming.startTime = Date()
        stopTime = nil
        isShowRunning = true
        logCall("Performance Started - Act 1", type: .action)
    }
    
    private func emergencyStop() {
        stopTime = Date()
        currentState = .stopped
        isShowRunning = false
        logCall("EMERGENCY STOP: \(stopReason)", type: .emergency)
        
        let stopRecord = ShowStop(
            timestamp: stopTime!,
            reason: stopReason,
            actNumber: currentState.actNumber ?? 1
        )
        performanceTiming.showStops.append(stopRecord)
    }
    
    private func endPerformance() {
        currentState = .completed
        performanceTiming.endTime = Date()
        stopTime = nil
        isShowRunning = false
        logCall("Performance Complete", type: .action)
        
        performance.timing = performanceTiming
        
        generatePerformanceReport()
        
        try? modelContext.save()
        
        // Dismiss the DSM view after a brief delay to show the completion state
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            dismiss()
        }
    }
    
    private func generatePerformanceReport() {
        let report = PerformanceReport(
            performanceId: performance.id,
            showTitle: performance.show?.title ?? "Unknown Show",
            performanceDate: performance.date,
            startTime: performanceTiming.startTime,
            endTime: performanceTiming.endTime,
            totalRuntime: performanceTiming.endTime?.timeIntervalSince(performanceTiming.startTime ?? Date()) ?? 0,
            currentState: currentState,
            callsExecuted: callsLog.count,
            cuesExecuted: calledCues.count,
            showStops: performanceTiming.showStops.count,
            emergencyStops: callsLog.filter { $0.type == .emergency }.count,
            callLogEntries: callsLog,
            cueExecutions: Array(calledCues),
            showStopDetails: performanceTiming.showStops
        )
        
        // Add contextual notes based on how the show ended
        if case .stopped = currentState {
            report.notes = "Performance ended with emergency stop: \(stopReason)"
        } else if performanceTiming.showStops.count > 0 {
            report.notes = "Performance completed with \(performanceTiming.showStops.count) show stop(s)."
        } else {
            report.notes = "Performance completed successfully without interruptions."
        }
        
        modelContext.insert(report)
    }
    
    private func startInterval() {
        currentState = .interval(intervalNumber: 1)
        logCall("End Act 1 - Interval", type: .action)
    }
    
    private func startNextAct() {
        currentState = .inProgress(actNumber: 2)
        stopTime = nil
        logCall("Act 2 - GO", type: .action)
    }
    
    private func loadAllCues() {
        allCues.removeAll()
        for line in sortedLinesCache {
            allCues.append(contentsOf: line.cues)
        }
    }
    
    private func scrollToCue(_ cue: Cue) {
        if let line = sortedLinesCache.first(where: { $0.id == cue.lineId }) {
            if scrollToChangesActiveLine {
                currentLineNumber = line.lineNumber
            }
        }
    }
    
    private func executeCue(_ cue: Cue) {
        if cue.type.cueTypeDisplay == "STANDBY" {
            logCall("STANDBY: \(cue.label)", type: .call)
        } else if cue.type.cueTypeDisplay == "WARNING" {
            logCall("WARNING: \(cue.label)", type: .call)
        } else {
            logCall("GO: \(cue.label)", type: .action)
        }
    }
    
    private func toggleCueCalled(_ cue: Cue) {
        if calledCues.contains(cue.id) {
            calledCues.remove(cue.id)
            hiddenCues.remove(cue.id)
            cueHideTimers[cue.id]?.invalidate()
            cueHideTimers.removeValue(forKey: cue.id)
            logCall("UNMARKED: \(cue.label)", type: .note)
        } else {
            calledCues.insert(cue.id)
            
            let execution = ReportCueExecution(
                timestamp: Date(),
                cueLabel: cue.label,
                cueType: cue.type.displayName,
                lineNumber: sortedLinesCache.first(where: { $0.id == cue.lineId })?.lineNumber ?? 0,
                executionMethod: "Manual"
            )
            cueExecutions.append(execution)
            
            if cue.hasAlert {
                showCueAlert()
            }
            
            logCall("MARKED: \(cue.label)", type: .call)
            
            let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    hiddenCues.insert(cue.id)
                }
                cueHideTimers.removeValue(forKey: cue.id)
            }
            cueHideTimers[cue.id] = timer
        }
    }
    
    private func executeNextCue() {
        let nextCue = findNextCueFromCurrentLine()
        
        guard let cue = nextCue else {
            logCall("REMOTE: No upcoming cues found", type: .note)
            return
        }
        
        calledCues.insert(cue.id)
        let execution = ReportCueExecution(
            timestamp: Date(),
            cueLabel: cue.label,
            cueType: cue.type.displayName,
            lineNumber: sortedLinesCache.first(where: { $0.id == cue.lineId })?.lineNumber ?? 0,
            executionMethod: "Remote Control"
        )
        cueExecutions.append(execution)
        
        if cue.type.cueTypeDisplay == "STANDBY" {
            logCall("REMOTE STANDBY: \(cue.label)", type: .call)
        } else if cue.type.cueTypeDisplay == "WARNING" {
            logCall("REMOTE WARNING: \(cue.label)", type: .call)
        } else {
            logCall("REMOTE GO: \(cue.label)", type: .action)
        }
    }
    
    private func findNextCueFromCurrentLine() -> Cue? {
        let visibleCues = sortedCuesCache.filter { !hiddenCues.contains($0.id) && !calledCues.contains($0.id) }
        
        for cue in visibleCues {
            if let cueLine = sortedLinesCache.first(where: { $0.id == cue.lineId }),
               cueLine.lineNumber >= currentLineNumber {
                return cue
            }
        }
        
        return visibleCues.first
    }
    
    private func moveToLine(_ lineNumber: Int) {
        guard lineNumber >= 1 && lineNumber <= sortedLinesCache.count else { return }
        currentLineNumber = lineNumber
        self.mqttManager.sendData(to: "shows/1/line", message: String(lineNumber))
    }
    
    private func logCall(_ message: String, type: CallLogEntry.CallType = .note) {
        let entry = CallLogEntry(timestamp: Date(), message: message, type: type)
        callsLog.append(entry)
    }
}

struct CallLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let type: CallType
    
    enum CallType {
        case call, action, emergency, note
        
        var color: Color {
            switch self {
            case .call: return .blue
            case .action: return .green
            case .emergency: return .red
            case .note: return .orange
            }
        }
    }
}

extension PerformanceState {
    var displayName: String {
        switch self {
        case .preShow: return "Pre-Show"
        case .houseOpen: return "House Open"
        case .clearance: return "Stage Clear"
        case .inProgress(let act): return "Act \(act) Running"
        case .interval(let interval): return "Interval \(interval)"
        case .completed: return "Show Complete"
        case .stopped: return "Show Stopped"
        }
    }
    
    var color: Color {
        switch self {
        case .preShow: return .gray
        case .houseOpen: return .blue
        case .clearance: return .orange
        case .inProgress: return .green
        case .interval: return .purple
        case .completed: return .green
        case .stopped: return .red
        }
    }
    
    var actNumber: Int? {
        switch self {
        case .inProgress(let actNumber): return actNumber
        default: return nil
        }
    }
}

extension CueType {
    var isStandby: Bool {
        switch self {
        case .lightingStandby, .soundStandby, .flyStandby, .automationStandby:
            return true
        default:
            return false
        }
    }
}


