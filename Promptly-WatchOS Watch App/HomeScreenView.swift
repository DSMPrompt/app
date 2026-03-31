//
//  HomeScreenView.swift
//  Promptly-WatchOS Watch App
//
//  Created by Sasha Bagrov on 05/10/2025.
//

import SwiftUI
import SwiftData

struct HomeScreenView: View {
    @State var navStackMessage: String = ""
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
            .sheet(isPresented: self.$showNetworkSettings) {
                NetworkSettingsView()
            }
        }
    }
    
    var content: some View {
        Group {
            List {
                Section(header: Text("Join a show")) {
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
                } header: {
                    Text("Connection Settings")
                } footer: {
                    Text("To apply changes, restart the app")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("")
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
