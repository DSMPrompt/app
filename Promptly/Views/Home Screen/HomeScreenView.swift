//
//  HomeScreenView.swift
//  Promptly
//
//  Created by Sasha Bagrov on 04/06/2025.
//

import SwiftUI
import SwiftData

struct HomeScreenView: View {
    @Query var shows: [Show] = []
    
    @Environment(\.modelContext) var modelContext
    
    @State var navStackMessage: String = ""
    @State var addShow: Bool = false
    @State var showNetworkSettings: Bool = false
    @State var availableShows: [String: String] = [:]
    
    @StateObject private var mqttManager = MQTTManager()
    
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
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    
                    TextField("MQTT Port", text: $mqttPort)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Connection Settings")
                } footer: {
                    Text("To apply changes, restart the app")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Network Settings")
            .navigationBarTitleDisplayMode(.inline)
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

#Preview {
    HomeScreenView()
}
