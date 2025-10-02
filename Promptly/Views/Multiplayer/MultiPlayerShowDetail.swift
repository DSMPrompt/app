//
//  MultiPlayerShowDetail.swift
//  Promptly
//
//  Created by Sasha Bagrov on 01/10/2025.
//

import SwiftUI

struct MultiPlayerShowDetail: View {
    var showID: String
    @StateObject var mqttManager: MQTTManager
    
    @State private var title: String?
    @State private var location: String?
    @State private var scriptName: String?
    @State private var status: String?
    @State private var dsmNetworkIP: String?
    @State private var isLoading = false
    
    @State private var receivedScript: Script? = nil
    @State private var showingShow = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let title = title {
                Text(title)
                    .font(.largeTitle)
                    .bold()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                if let location = location {
                    HStack {
                        Text("Location:")
                            .foregroundColor(.secondary)
                        Text(location)
                    }
                }
                
                if let scriptName = scriptName {
                    HStack {
                        Text("Script:")
                            .foregroundColor(.secondary)
                        Text(scriptName)
                    }
                }
                
                if let status = status {
                    HStack {
                        Text("Status:")
                            .foregroundColor(.secondary)
                        Text(status)
                            .foregroundColor(status == "active" ? .green : .orange)
                    }
                }
                
                if let dsmNetworkIP = dsmNetworkIP {
                    HStack {
                        Text("DSM Network IP:")
                            .foregroundColor(.secondary)
                        Text(dsmNetworkIP)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                if receivedScript != nil {
                    showingShow = true
                } else {
                    isLoading = true
                    fetchNetwork() { script in
                        if let script = script {
                            self.receivedScript = script
                        }
                    }
                }
            }) {
                Text(receivedScript != nil ? "Join Show" : "Join")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
        .padding()
        .fullScreenCover(isPresented: $isLoading) {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }
        }
        .fullScreenCover(isPresented: $showingShow) {
            if let script = self.receivedScript {
                SpectatorPerformanceView(showId: UUID(uuidString: self.showID)!, script: script, mqttManager: self.mqttManager)
            }
        }
        .onAppear {
            loadShow()
        }
    }
    
    private func loadShow() {
        mqttManager.getShow(id: showID) { title, location, scriptName, status, dsmNetworkIP in
            self.title = title
            self.location = location
            self.scriptName = scriptName
            self.status = status
            self.dsmNetworkIP = dsmNetworkIP
        }
    }
    
    private func fetchNetwork(completion: @escaping (Script?) -> Void) {
        guard let dsmNetworkIP = dsmNetworkIP,
              let url = URL(string: "http://\(dsmNetworkIP):8080") else {
            isLoading = false
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                guard let data = data, error == nil,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let script = Script(from: json) else {
                    completion(nil)
                    return
                }
                
                completion(script)
            }
        }.resume()
    }
}
