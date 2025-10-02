//
//  SpectatorPerformaceView.swift
//  Promptly
//
//  Created by Sasha Bagrov on 01/10/2025.
//

import SwiftUI
import SwiftData

struct SpectatorPerformanceView: View {
    let showId: UUID
    let script: Script
    
    @StateObject var mqttManager: MQTTManager
    @State private var currentLine: Int = 1
    @State private var status: PerformanceState = .preShow
    @State private var calledCues: Set<UUID> = []
    @State private var timeCalls: String = ""
    @State private var sortedLinesCache: [ScriptLine] = []
    @State private var currentTime = Date()
    @State private var showingTimeCall = false
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                spectatorHeader
                
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(sortedLinesCache, id: \.id) { line in
                                DSMScriptLineView(
                                    line: line,
                                    isCurrent: line.lineNumber == currentLine,
                                    onLineTap: {},
                                    calledCues: calledCues
                                )
                                .id("line-\(line.lineNumber)")
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .background(Color(.systemBackground))
                    .onChange(of: currentLine) { _, newValue in
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("line-\(newValue)", anchor: .center)
                        }
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showingTimeCall) {
            TimeCallOverlay(message: timeCalls) {
                showingTimeCall = false
            }
        }
        .onAppear {
            sortedLinesCache = script.lines.sorted { $0.lineNumber < $1.lineNumber }
            
            mqttManager.subscribe(to: "shows/\(showId.uuidString)/line") { message in
                if let lineNum = Int(message) {
                    currentLine = lineNum
                }
            }
            
            mqttManager.subscribe(to: "shows/\(showId.uuidString)/status") { message in
                status = PerformanceState(displayName: message)
            }
            
            mqttManager.subscribe(to: "shows/\(showId.uuidString)/calledCues") { message in
                guard let data = message.data(using: .utf8),
                      let uuidStrings = try? JSONDecoder().decode([String].self, from: data)
                else { return }
                
                calledCues = Set(uuidStrings.compactMap { UUID(uuidString: $0) })
            }
            
            mqttManager.subscribe(to: "shows/\(showId.uuidString)/timeCalls") { message in
                timeCalls = message
                if !message.isEmpty {
                    showingTimeCall = true
                }
            }
            
            if let deviceUUID = UUID(uuidString: UserDefaults.standard.string(forKey: "deviceUUID") ?? "") {
                mqttManager.broadcastDevice(
                    showId: showId.uuidString,
                    deviceUUID: deviceUUID
                )
            }
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
        .onChange(of: self.status) { oldStatus, newStatus in
            if newStatus == .completed {
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    if let deviceUUID = UUID(uuidString: UserDefaults.standard.string(forKey: "deviceUUID") ?? "") {
                        mqttManager.removeDevice(
                            showId: showId.uuidString,
                            deviceUUID: deviceUUID
                        )
                    }
                    dismiss()
                }
            }
        }
    }
    
    private var spectatorHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(script.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Text(status.displayName)
                        .font(.caption)
                        .foregroundColor(status.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(status.color.opacity(0.2))
                        .cornerRadius(4)
                    
                    Text("Spectator Mode")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(currentTime.formatted(date: .omitted, time: .standard))
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(.primary)
                
                Text("Line \(currentLine)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
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
}

struct TimeCallOverlay: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack {
            Color.red
                .ignoresSafeArea()
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                    }
                    .padding(30)
                }
                
                Spacer()
                
                Text(message)
                    .font(.system(size: 80, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(40)
                
                Spacer()
            }
        }
    }
}
