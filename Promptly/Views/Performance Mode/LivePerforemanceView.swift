import SwiftUI
import SwiftData
import Foundation
import Network
import Darwin
import Combine
import MIDIKitIO

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
    @State private var goToLine = ""
    @State private var showingGoToLineAlert = false
    @State private var callsLog: [CallLogEntry] = []
    @State private var currentLineNumber = 1
    @State private var scrollToLineNumber: Int? = 1
    @State private var allCues: [Cue] = []
    @State private var calledCues: Set<UUID> = []
    @State private var hiddenCues: Set<UUID> = []
    @State private var cueHideTimers: [UUID: Timer] = [:]
    @State private var showingDetails = false
    @State private var showingSettings = false
    @State private var showingResetScrollButton = false
    @State private var showingRemoteSettingsAlert: Bool = false
    @State private var showingBluetoothSettings = false
    @State private var showingGoToSectionSheet = false
    @State private var keepDisplayAwake = true
    @State private var showAlertWhenEndingShowWithPause = false
    @State private var scrollToChangesActiveLine = false
    @State private var currentTime = Date()
    @State private var stopTime: Date?
    @State private var cueExecutions: [ReportCueExecution] = []
    @State private var showingCueAlert = false
    @State private var cueAlertTimer: Timer?
    @State private var uuidOfShow: String = ""
    @State private var showingMIDISettings = false
    @FocusState private var isViewFocused: Bool
    @StateObject private var bluetoothManager = PromptlyBluetoothManager()
    @StateObject private var mqttManager = MQTTManager()
    @StateObject private var jsonServer = JSONServer(port: 8080)

    
    @Environment(ObservableMIDIManager.self) private var midiManager
    @Environment(MIDIHelper.self) private var midiHelper
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    private var script: Script? {
        performance.show?.script
    }
    
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
        mainContentView
            .sheet(isPresented: $showingMIDISettings) {
                MIDIConfigurationView(midiHelper: midiHelper)
            }
            .alert("Which type?", isPresented: self.$showingRemoteSettingsAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Bluetooth") {
                    self.showingBluetoothSettings = true
                }
                Button("MIDI") {
                    self.showingMIDISettings = true
                }
            }
            .alert("Go To Line (set active)", isPresented: self.$showingGoToLineAlert) {
                TextField("Line", text: self.$goToLine)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                Button("Cancel", role: .cancel) { }
                Button("Go To", role: .destructive) {
                    self.moveToLine(Int(self.goToLine) ?? 0)
                    self.goToLine = ""
                }
            }
            .applyDSMCore(
                isViewFocused: $isViewFocused,
                onAppear: setupView,
                onDisappear: cleanupView,
                timer: timer,
                currentTime: $currentTime
            )
            .applyDSMKeyboard(
                sortedLinesCache: sortedLinesCache,
                currentLineNumber: currentLineNumber,
                onLineMove: moveToLine
            )
            .applyDSMObservers(
                allCues: allCues,
                hiddenCues: hiddenCues,
                sortedLinesCache: sortedLinesCache,
                script: script,
                currentState: $currentState,
                onCacheUpdate: updateCuesCache,
                onScriptChange: handleScriptChange,
                onStateChange: handleStateChange
            )
            .applyDSMAlerts(
                showingStopAlert: $showingStopAlert,
                showingEndConfirmation: $showingEndConfirmation,
                showingBluetoothSettings: $showingBluetoothSettings,
                showingSettings: $showingSettings,
                showingDetails: $showingDetails,
                stopReason: $stopReason,
                keepDisplayAwake: $keepDisplayAwake,
                scrollToChangesActiveLine: $scrollToChangesActiveLine,
                performance: performance,
                showId: uuidOfShow,
                mqttManager: mqttManager,
                timing: $performanceTiming,
                callsLog: $callsLog,
                currentState: $currentState,
                isShowRunning: $isShowRunning,
                canMakeQuickCalls: canMakeQuickCalls,
                bluetoothManager: bluetoothManager,
                showAlertWhenEndingShowWithPause: $showAlertWhenEndingShowWithPause,
                endPerformanceWithoutEnd: endPerformanceWithoutEnd,
                onStartShow: startShow,
                onStopShow: { showingStopAlert = true },
                onEndShow: { showingEndConfirmation = true },
                onStartInterval: startInterval,
                onStartNextAct: startNextAct,
                onEmergencyStop: emergencyStop,
                onEndPerformance: endPerformance,
                goToLine: goToLine,
                showingGoToSectionSheet: $showingGoToSectionSheet
            )
    }

    private var mainContentView: some View {
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
                        #if os(iOS)
            .background(Color(uiColor: .systemBackground))
            #endif
            #if os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
            #endif

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
    }

    private func setupView() {
        isViewFocused = true
        
        if keepDisplayAwake {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        sortedLinesCache = script?.lines.sorted { $0.lineNumber < $1.lineNumber } ?? []
        updateLinesCache()
        loadAllCues()
        updateCuesCache()
        
        mqttManager.connect(to: Constants.mqttIP, port: Constants.mqttPort)
        
        if let show = performance.show {
            guard let scriptDict = show.script?.toDictionary() else {
                print("well fuck uhhhh my guy u are cookido")
                return
            }
            jsonServer.start(dataToServe: scriptDict)
            
            mqttManager.sendOutShow(
                id: show.id.uuidString,
                title: show.title,
                location: show.locationString,
                scriptName: show.script?.name,
                status: currentState,
                dsmNetworkIP: getLocalIPAddress() ?? "N/A"
            )
            
            let showUUID = show.id.uuidString
            print("🎭 Setting uuidOfShow to: '\(showUUID)'")
            uuidOfShow = showUUID
            
            print("🎭 Sending initial line with UUID: '\(showUUID)'")
            mqttManager.sendData(to: "shows/\(showUUID)/line", message: "1")
        }
        
        // Existing Bluetooth setup
        bluetoothManager.onButtonPress = { value in
            handleRemoteButtonPress(value)
        }
        
        // NEW: MIDI setup using the same handler
        midiHelper.onButtonPress = { value in
            handleRemoteButtonPress(value)
        }
    }
    
    private func handleRemoteButtonPress(_ value: String) {
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

    private func cleanupView() {
        UIApplication.shared.isIdleTimerDisabled = false
        for timer in cueHideTimers.values {
            timer.invalidate()
        }
        cueHideTimers.removeAll()
        cueAlertTimer?.invalidate()
    }

    private func handleStateChange() {
        mqttManager.sendData(to: "shows/\(uuidOfShow)/status", message: currentState.displayName)
    }

    private func handleScriptChange() {
        updateLinesCache()
        loadAllCues()
        updateCuesCache()
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
                if self.showingResetScrollButton {
                    Button {
                        self.scrollToLineNumber = self.currentLineNumber
                        self.showingResetScrollButton = false
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.scrollToLineNumber = nil
                        }
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.bordered)
                }
                
                Menu(content: {
                    Button(action: {
                        showingRemoteSettingsAlert = true
                    }) {
                        Label(
                            "Remotes",
                            systemImage: "antenna.radiowaves.left.and.right"
                        )
                    }
                    
                    Button {
                        showingSettings = true
                    } label: {
                        Label(
                            "Settings",
                            systemImage: "gear"
                        )
                    }
                }, label: {
                    Image(systemName: "ellipsis.circle")
                })
                .buttonStyle(.bordered)
                
                Button("Details") {
                    showingDetails = true
                }
                .buttonStyle(.bordered)
                
                // Stop / start button
                if isShowRunning {
                    Button("E STOP", role: .destructive) {
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
                            self.showingGoToLineAlert = true
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
    
    private var scriptContentView: some View {
        let showUUID = self.uuidOfShow
        
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(sortedLinesCache, id: \.id) { line in
                        DSMScriptLineView(
                            line: line,
                            isCurrent: line.lineNumber == currentLineNumber,
                            onLineTap: {
                                currentLineNumber = line.lineNumber
                                self.mqttManager.sendData(to: "shows/\(showUUID)/line", message: "\(line.lineNumber)")
                            },
                            calledCues: calledCues
                        )
                        .id("line-\(line.lineNumber)")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            #if os(iOS)
            .background(Color(uiColor: .systemBackground))
            #endif
            #if os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
            #endif
            .onChange(of: currentLineNumber) { _, newValue in
                proxy.scrollTo("line-\(newValue)", anchor: .center)
            }
            .onChange(of: scrollToLineNumber) { _, newValue in
                print("got value (new) to scroll to: \(String(describing: newValue))")
                if let value = newValue {
                    proxy.scrollTo("line-\(value)", anchor: .center)
                    print("scrolled")
                    if value != currentLineNumber {
                        self.showingResetScrollButton = true
                        print("button reset")
                    }
                }
            }
            .onScrollPhaseChange { a, b in
                if a.isScrolling {
                    withAnimation(.interactiveSpring) {
                        self.showingResetScrollButton = true
                    }
                }
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
    
    func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        
        guard getifaddrs(&ifaddr) == 0 else { return nil }
        guard let firstAddr = ifaddr else { return nil }
        
        defer { freeifaddrs(ifaddr) }
        
        for ifptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ifptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                
                if name == "en0" || name == "en1" || name.starts(with: "en") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr,
                               socklen_t(interface.ifa_addr.pointee.sa_len),
                               &hostname,
                               socklen_t(hostname.count),
                               nil,
                               socklen_t(0),
                               NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        
        return address
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
                        .fill(Color(hex: cue.type.color))
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
                    
                    Button(cue.type.isStandby ? "STANDBY" : "GO") {
                        onExecute()
                    }
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(isCalled ? Color.gray : (cue.type.isStandby ? Color.orange : Color.green))
                    .cornerRadius(6)
                    .disabled(isCalled)
                }
            }
            .padding()
            .background(isCalled ? Color(.systemGray6) : Color(.systemBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isCalled ? Color.gray : Color(hex: cue.type.color), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct DSMDetailsView: View {
    let performance: Performance
    let showId: String
    @ObservedObject var mqttManager: MQTTManager
    @Binding var timing: PerformanceTiming
    @Binding var callsLog: [CallLogEntry]
    @Binding var currentState: PerformanceState
    @Binding var isShowRunning: Bool
    @Binding var showAlertWhenEndingShowWithPause: Bool
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
                                        self.mqttManager.sendData(to: "shows/\(showId)/timeCalls", message: "House Open")
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
                                        self.mqttManager.sendData(to: "shows/\(showId)/timeCalls", message: "Stage Clear")
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
                                    self.mqttManager.sendData(to: "shows/\(showId)/timeCalls", message: "Half Hour Call (35 min)")
                                }
                                DSMCallButton(title: "Quarter Hour", time: "20 min") {
                                    logCall("Quarter Hour Call", type: .call)
                                    self.mqttManager.sendData(to: "shows/\(showId)/timeCalls", message: "Quarter Hour Call (20 min)")
                                }
                                DSMCallButton(title: "Five Minutes", time: "10 min") {
                                    logCall("Five Minutes Call", type: .call)
                                    self.mqttManager.sendData(to: "shows/\(showId)/timeCalls", message: "Five Minutes Call (10 min)")
                                }
                                DSMCallButton(title: "Beginners", time: "5 min") {
                                    logCall("Beginners Call", type: .call)
                                    self.mqttManager.sendData(to: "shows/\(showId)/timeCalls", message: "Beginners Call (5 min)")
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
                        #if os(iOS)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                        #endif
                        #if os(macOS)
                        .background(Color(nsColor: .controlBackgroundColor))
                        #endif
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Pause and End") {
                        self.showAlertWhenEndingShowWithPause = true
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
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
            #if os(iOS)
            .background(Color(uiColor: .systemBackground))
            #endif
            #if os(macOS)
            .background(Color(nsColor: .windowBackgroundColor))
            #endif
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
        #if os(iOS)
        .background(Color(uiColor: .systemBackground))
        #endif
        #if os(macOS)
        .background(Color(nsColor: .windowBackgroundColor))
        #endif
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.mqttManager.removeShow(id: self.uuidOfShow)
            self.jsonServer.stop()
            dismiss()
        }
    }
    
    private func endPerformanceWithoutEnd() {
        isShowRunning = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.mqttManager.removeShow(id: self.uuidOfShow)
            self.jsonServer.stop()
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
            } else {
                scrollToLineNumber = line.lineNumber
            }
        }
    }
    
    private func executeCue(_ cue: Cue) {
        if cue.type.isStandby {
            logCall("STANDBY: \(cue.label)", type: .call)
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
        
        // SEND THE UPDATE HERE
        let uuidStrings = calledCues.map { $0.uuidString }
        if let jsonData = try? JSONEncoder().encode(uuidStrings),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            mqttManager.sendData(to: "shows/\(uuidOfShow)/calledCues", message: jsonString)
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
        
        if cue.hasAlert {
            showCueAlert()
        }
        
        if cue.type.isStandby {
            logCall("REMOTE STANDBY: \(cue.label)", type: .call)
        } else {
            logCall("REMOTE GO: \(cue.label)", type: .action)
        }
        
        let timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            withAnimation(.easeOut(duration: 0.3)) {
                hiddenCues.insert(cue.id)
            }
            cueHideTimers.removeValue(forKey: cue.id)
        }
        cueHideTimers[cue.id] = timer
        
        let uuidStrings = calledCues.map { $0.uuidString }
        if let jsonData = try? JSONEncoder().encode(uuidStrings),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            mqttManager.sendData(to: "shows/\(uuidOfShow)/calledCues", message: jsonString)
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
        
        var targetLineNumber = lineNumber
        let isMovingForward = targetLineNumber > currentLineNumber
        
        while targetLineNumber >= 1 && targetLineNumber <= sortedLinesCache.count {
            let targetLine = sortedLinesCache[targetLineNumber - 1]
            
            if targetLine.flags.contains(.skip) {
                if isMovingForward {
                    targetLineNumber += 1
                } else {
                    targetLineNumber -= 1
                }
            } else {
                break
            }
        }
        
        targetLineNumber = max(1, min(targetLineNumber, sortedLinesCache.count))
        
        currentLineNumber = targetLineNumber
        self.mqttManager.sendData(to: "shows/\(self.uuidOfShow)/line", message: String(targetLineNumber))
    }
    
    private func logCall(_ message: String, type: CallLogEntry.CallType = .note) {
        let entry = CallLogEntry(timestamp: Date(), message: message, type: type)
        callsLog.append(entry)
    }
    
    func goToLine(_ lineNumber: Int) {
        moveToLine(lineNumber)
    }
}

extension View {
    // Core navigation and appearance
    func applyDSMCore(
        isViewFocused: FocusState<Bool>.Binding,
        onAppear: @escaping () -> Void,
        onDisappear: @escaping () -> Void,
        timer: Publishers.Autoconnect<Timer.TimerPublisher>,
        currentTime: Binding<Date>
    ) -> some View {
        self
            #if os(iOS)
            .navigationBarHidden(true)
            #endif
            .preferredColorScheme(.dark)
            .focusable()
            .focused(isViewFocused)
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
            .onReceive(timer) { _ in currentTime.wrappedValue = Date() }
    }
    
    // Keyboard navigation
    func applyDSMKeyboard(
        sortedLinesCache: [ScriptLine],
        currentLineNumber: Int,
        onLineMove: @escaping (Int) -> Void
    ) -> some View {
        self
            .onKeyPress(.downArrow) {
                let next = sortedLinesCache.first(where: { $0.lineNumber > currentLineNumber })?.lineNumber
                let fallback = sortedLinesCache.last?.lineNumber ?? 1
                withAnimation(.easeOut(duration: 0.1)) { onLineMove(next ?? fallback) }
                return .handled
            }
            .onKeyPress(.upArrow) {
                let prev = sortedLinesCache.last(where: { $0.lineNumber < currentLineNumber })?.lineNumber
                let fallback = sortedLinesCache.first?.lineNumber ?? 1
                withAnimation(.easeOut(duration: 0.1)) { onLineMove(prev ?? fallback) }
                return .handled
            }
    }
    
    // Data change observers
    func applyDSMObservers(
        allCues: [Cue],
        hiddenCues: Set<UUID>,
        sortedLinesCache: [ScriptLine],
        script: Script?,
        currentState: Binding<PerformanceState>,
        onCacheUpdate: @escaping () -> Void,
        onScriptChange: @escaping () -> Void,
        onStateChange: @escaping () -> Void
    ) -> some View {
        self
            .onChange(of: allCues) { _, _ in onCacheUpdate() }
            .onChange(of: hiddenCues) { _, _ in onCacheUpdate() }
            .onChange(of: sortedLinesCache) { _, _ in onCacheUpdate() }
            .onChange(of: script) { _, _ in onScriptChange() }
            .onChange(of: currentState.wrappedValue) { _, _ in onStateChange() }
    }
    
    // Alerts and modals
    func applyDSMAlerts(
        showingStopAlert: Binding<Bool>,
        showingEndConfirmation: Binding<Bool>,
        showingBluetoothSettings: Binding<Bool>,
        showingSettings: Binding<Bool>,
        showingDetails: Binding<Bool>,
        stopReason: Binding<String>,
        keepDisplayAwake: Binding<Bool>,
        scrollToChangesActiveLine: Binding<Bool>,
        performance: Performance,
        showId: String,
        mqttManager: MQTTManager,
        timing: Binding<PerformanceTiming>,
        callsLog: Binding<[CallLogEntry]>,
        currentState: Binding<PerformanceState>,
        isShowRunning: Binding<Bool>,
        canMakeQuickCalls: Bool,
        bluetoothManager: PromptlyBluetoothManager,
        showAlertWhenEndingShowWithPause: Binding<Bool>,
        endPerformanceWithoutEnd: @escaping () -> Void,
        onStartShow: @escaping () -> Void,
        onStopShow: @escaping () -> Void,
        onEndShow: @escaping () -> Void,
        onStartInterval: @escaping () -> Void,
        onStartNextAct: @escaping () -> Void,
        onEmergencyStop: @escaping () -> Void,
        onEndPerformance: @escaping () -> Void,
        goToLine: @escaping (Int) -> Void,
        showingGoToSectionSheet: Binding<Bool>
    ) -> some View {
        self
            .alert("Emergency Stop", isPresented: showingStopAlert) {
                TextField("Reason", text: stopReason)
                Button("Cancel", role: .cancel) { }
                Button("Stop Show", role: .destructive, action: onEmergencyStop)
            }
            .alert("End Performance", isPresented: showingEndConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("End Show", action: onEndPerformance)
            }
            .sheet(isPresented: showingBluetoothSettings) {
                PromptlyBluetoothSettingsView(bluetoothManager: bluetoothManager)
            }
            .sheet(isPresented: showingSettings) {
                DSMSettingsView(keepDisplayAwake: keepDisplayAwake, scrollToChangesActiveLine: scrollToChangesActiveLine)
            }
            .sheet(isPresented: showingDetails) {
                DSMDetailsView(
                    performance: performance,
                    showId: showId,
                    mqttManager: mqttManager,
                    timing: timing,
                    callsLog: callsLog,
                    currentState: currentState,
                    isShowRunning: isShowRunning,
                    showAlertWhenEndingShowWithPause: showAlertWhenEndingShowWithPause,
                    canMakeQuickCalls: canMakeQuickCalls,
                    onStartShow: onStartShow,
                    onStopShow: onStopShow,
                    onEndShow: onEndShow,
                    onStartInterval: onStartInterval,
                    onStartNextAct: onStartNextAct
                )
            }
            .alert("You are ending a show with pause - no performace reports will be generated", isPresented: showAlertWhenEndingShowWithPause) {
                Button("Cancel", role: .cancel) { }
                Button("Pause and End show", action: endPerformanceWithoutEnd)
            }
            .sheet(isPresented: showingGoToSectionSheet) {
                DSMGoToSection(performance: performance, goToLine: goToLine)
            }
    }
}

struct DSMGoToSection: View {
    let performance: Performance
    var goToLine: (Int) -> Void
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            Group {
                if let sections = self.performance.show?.script?.sections {
                    ForEach(sections, id: \.id) { section in
                        Button {
                            self.goToLine(section.startLineNumber)
                            dismiss()
                        } label: {
                            Label(
                                "\(section.title)",
                                systemImage: ""
                            )
                        }
                    }
                } else {
                    Text("No sections found!")
                }
            }
            .navigationTitle("Go To Section")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem {
                    Button {
                        dismiss()
                    } label: {
                        Label(
                            "Dismiss",
                            systemImage: ""
                        )
                    }
                }
            }
        }
    }
}

struct MIDIConfigurationView: View {
    let midiHelper: MIDIHelper
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section("MIDI Program Change Mapping") {
                    ForEach(0...32, id: \.self) { program in
                        HStack {
                            Text("PC \(program)")
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 60, alignment: .leading)
                            
                            Picker("Action", selection: Binding(
                                get: {
                                    midiHelper.programChangeMapping[program] ?? .none
                                },
                                set: {
                                    midiHelper.mapProgramChange(program, to: $0)
                                }
                            )) {
                                ForEach(MIDIHelper.RemoteAction.allCases, id: \.self) { action in
                                    Text(action.rawValue).tag(action)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
                
                Section {
                    Text("Map MIDI Program Change messages (0-32) to remote actions. Use your MIDI controller to send Program Change messages on any channel.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } header: {
                    Text("Instructions")
                }
            }
            .navigationTitle("MIDI Remote")
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
}
