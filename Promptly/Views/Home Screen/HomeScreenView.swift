//
//  HomeScreenView.swift
//  Promptly
//
//  Created by Sasha Bagrov on 04/06/2025.
//

import SwiftUI
import SwiftData
import MIDIKitIO
import UniformTypeIdentifiers
import WhatsNewKit

struct HomeScreenView: View {
    @Query var shows: [Show] = []
    
    @Environment(\.modelContext) var modelContext
    
    @State var navStackMessage: String = ""
    @State var addShow: Bool = false
    @State var showNetworkSettings: Bool = false
    @State var showingImportShowSheet = false
    @State var importError: ImportError?
    @State var availableShows: [String: String] = [:]
    
    @StateObject private var mqttManager = MQTTManager()
    @Environment(ObservableMIDIManager.self) private var midiManager
    @Environment(MIDIHelper.self) private var midiHelper
    
    var body: some View {
        NavigationStack {
            Group {
                self.content
            }
            .navigationTitle(Text(
                self.navStackMessage
            ))
            .toolbar {
                ToolbarItemGroup {
                    self.toolbarContent
                }
            }
            .onAppear {
                self.setupGreeting()
                
                mqttManager.connect(to: Constants.mqttIP, port: Constants.mqttPort)
                
                mqttManager.subscribeToShowChanges { showId, property, message, title in
                    if UUID(uuidString: showId) != nil && availableShows[showId] == nil {
                        availableShows[showId] = title ?? "Unknown Show"
                    }
                }
            }
            .sheet(isPresented: self.$addShow) {
                AddShowViewWrapper()
            }
            .sheet(isPresented: self.$showNetworkSettings) {
                NetworkSettingsView()
            }
            .fileImporter(
                isPresented: $showingImportShowSheet,
                allowedContentTypes: [.dsmPrompt],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    
                    do {
                        let importedShow = try ShowImportManager.importShowFromFile(from: url, into: modelContext)
                        print("✅ Show imported successfully: \(importedShow.title)")
                    } catch {
                        print("❌ Import failed: \(error)")
                        importError = error as? ImportError ?? .invalidFileFormat
                    }
                case .failure(let error):
                    print("❌ File selection failed: \(error)")
                    importError = .invalidFileFormat
                }
            }
            .alert("Import Error", isPresented: Binding<Bool>(
                get: { importError != nil },
                set: { _ in importError = nil }
            )) {
                Button("OK") { importError = nil }
            } message: {
                if let error = importError {
                    Text(error.localizedDescription)
                }
            }
            .whatsNewSheet()
        }
    }
    
    var content: some View {
        Group {
            List {
                Section(header: Text(
                    "Select a show"
                )) {
                    if self.shows.isEmpty {
                        ContentUnavailableView(
                            "No shows saved",
                            systemImage: "xmark.circle",
                            description: Text(
                                "Start by creating a show by clicking the plus icon in the top right hand corner."
                            )
                        )
                    } else {
                        ForEach(self.shows) { show in
                            NavigationLink(destination: ShowDetailView(show: show)) {
                                Text(show.title)
                            }
                        }
                    }
                }
                
                Section(header: Text("Or join a show")) {
                    if availableShows.isEmpty {
                        Text("No available shows")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(availableShows.keys), id: \.self) { showId in
                            NavigationLink(destination: MultiPlayerShowDetail(showID: showId, mqttManager: self.mqttManager)) {
                                Text(availableShows[showId] ?? "Unknown Show")
                            }
                        }
                    }
                }
            }
        }
    }
    
    var toolbarContent: some View {
        Group {
            Button {
                self.showNetworkSettings = true
            } label: {
                Label("Network Settings", systemImage: "network")
            }
            
            #if os(iOS)
            NavigationLink(
                destination: BluetoothMIDIView()
                    .navigationTitle("Remote Peripheral Config")
            ) {
                Label("MIDI", systemImage: "av.remote")
            }
            #endif
            
            Button {
                showingImportShowSheet = true
            } label: {
                Label("Import Show", systemImage: "square.and.arrow.down")
            }
            
            Button {
                self.addShow = true
            } label: {
                Label("Add Show", systemImage: "plus")
            }
        }
    }
    
    private func setupGreeting() {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 5 && hour < 12 {
            self.navStackMessage = "Good Morning"
        } else if hour >= 12 && hour < 17 {
            self.navStackMessage = "Good Afternoon"
        } else if hour >= 17 && hour < 21 {
            self.navStackMessage = "Good Evening"
        } else {
            self.navStackMessage = "Good Night"
        }
    }
}

struct NetworkSettingsView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var mqttIP: String = Constants.mqttIP
    @State private var mqttPort: String = String(Constants.mqttPort)
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("MQTT IP Address", text: $mqttIP)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    
                    TextField("MQTT Port", text: $mqttPort)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                } header: {
                    Text("Connection Settings")
                } footer: {
                    Text("To apply changes, restart the app")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Network Settings")
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
                        if let port = Int(mqttPort) {
                            Constants.mqttIP = mqttIP
                            Constants.mqttPort = port
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

extension ImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidFileFormat:
            return "Invalid file format. Please select a valid .dsmprompt file."
        case .corruptedData:
            return "The file appears to be corrupted and cannot be imported."
        case .unsupportedVersion:
            return "This file was created with a newer version of the app."
        case .missingRequiredFields:
            return "The file is missing required data and cannot be imported."
        }
    }
}

#Preview {
    HomeScreenView()
}
