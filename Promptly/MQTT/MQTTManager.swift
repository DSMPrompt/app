//
//  MQTTManager.swift
//  Promptly
//
//  Created by Sasha Bagrov on 28/09/2025.
//

import Foundation
import MQTTNIO
import Combine

class MQTTManager: ObservableObject {
    private var client: MQTTClient?
    
    @Published var isConnected = false
    @Published var receivedMessages: [String: String] = [:]
    
    private var messageHandlers: [String: (String) -> Void] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var updateTimers: [String: DispatchSourceTimer] = [:]
    private var deviceHeartbeatTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.promptly.mqtt.timers", qos: .background)
    
    func connect(to host: String, port: Int = 1883) {
        client = MQTTClient(
            configuration: .init(
                target: .host(host, port: port),
                protocolVersion: .version3_1_1
            ),
            eventLoopGroupProvider: .createNew
        )
        
        setupEventHandlers()
        client?.connect()
    }
    
    private func setupEventHandlers() {
        client?.connectPublisher.sink { [weak self] response in
            DispatchQueue.main.async {
                self?.isConnected = true
            }
        }.store(in: &cancellables)
        
        client?.disconnectPublisher.sink { [weak self] reason in
            DispatchQueue.main.async {
                self?.isConnected = false
            }
        }.store(in: &cancellables)
        
        client?.messagePublisher.sink { [weak self] message in
            let messageString = message.payload.string ?? ""
            
            DispatchQueue.main.async {
                self?.receivedMessages[message.topic] = messageString
                
                if let handler = self?.messageHandlers[message.topic] {
                    handler(messageString)
                }
            }
        }.store(in: &cancellables)
    }
    
    func disconnect() {
        updateTimers.values.forEach { $0.cancel() }
        updateTimers.removeAll()
        deviceHeartbeatTimer?.cancel()
        deviceHeartbeatTimer = nil
        client?.disconnect()
    }
    
    func sendData(to topic: String, message: String) {
        client?.publish(message, to: topic, qos: .atLeastOnce)
    }
    
    func subscribe(to topic: String, onMessage: @escaping (String) -> Void) {
        messageHandlers[topic] = onMessage
        client?.subscribe(to: topic)
    }
    
    func unsubscribe(from topic: String) {
        messageHandlers.removeValue(forKey: topic)
        client?.unsubscribe(from: topic)
    }
    
    func subscribeToShowChanges(onChange: @escaping (String, String, String, String?) -> Void) {
        let showsPattern = "shows/#"
        
        client?.messagePublisher
            .filter { message in
                let components = message.topic.split(separator: "/")
                return components.count >= 2 && components.first == "shows"
            }
            .sink { [weak self] message in
                let topic = message.topic
                let messageString = message.payload.string ?? ""
                let components = topic.split(separator: "/").map(String.init)
                
                guard components.count >= 2 else { return }
                
                let showId = components[1]
                let property = components.count > 2 ? components[2] : ""
                let title = self?.receivedMessages["shows/\(showId)/title"]
                
                DispatchQueue.main.async {
                    onChange(showId, property, messageString, title)
                }
            }
            .store(in: &cancellables)
        
        client?.subscribe(to: showsPattern)
    }
    
    func getShow(id: String, completion: @escaping (String?, String?, String?, String?, String?) -> Void) {
        let title = receivedMessages["shows/\(id)/title"]
        let location = receivedMessages["shows/\(id)/location"]
        let scriptName = receivedMessages["shows/\(id)/scriptName"]
        let status = receivedMessages["shows/\(id)/status"]
        let dsmNetworkIP = receivedMessages["shows/\(id)/dsmNetworkIP"]
        
        completion(title, location, scriptName, status, dsmNetworkIP)
    }
    
    func sendOutShow(id: String, title: String?, location: String?, scriptName: String?, status: PerformanceState?, dsmNetworkIP: String?) {
        if let title = title {
            sendData(to: "shows/\(id)/title", message: title)
        }
        if let location = location {
            sendData(to: "shows/\(id)/location", message: location)
        }
        if let scriptName = scriptName {
            sendData(to: "shows/\(id)/scriptName", message: scriptName)
        }
        if let dsmNetworkIP = dsmNetworkIP {
            sendData(to: "shows/\(id)/dsmNetworkIP", message: dsmNetworkIP)
        }
        if let status = status {
            sendData(to: "shows/\(id)/status", message: status.displayName)
        }
        
        sendData(to: "shows/\(id)/line", message: "0")
        sendData(to: "shows/\(id)/calledCues", message: "[]")
        sendData(to: "shows/\(id)/timeCalls", message: "")
        
        sendData(to: "shows/\(id)", message: "updated")
        
        startPeriodicUpdate(for: id)
    }
    
    func removeShow(id: String) {
        stopPeriodicUpdate(for: id)
        
        let topics = [
            "shows/\(id)/title",
            "shows/\(id)/location",
            "shows/\(id)/scriptName",
            "shows/\(id)/dsmNetworkIP",
            "shows/\(id)/status",
            "shows/\(id)/line",
            "shows/\(id)/calledCues",
            "shows/\(id)/timeCalls",
            "shows/\(id)"
        ]
        
        topics.forEach { topic in
            client?.publish("", to: topic, qos: .atLeastOnce, retain: true)
        }
    }
    
    func broadcastDevice(showId: String, deviceUUID: UUID) {
        let topic = "shows/\(showId)/devices/\(deviceUUID.uuidString)"
        
        deviceHeartbeatTimer?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: 30)
        timer.setEventHandler { [weak self] in
            self?.sendData(to: topic, message: "heartbeat")
        }
        timer.resume()
        
        deviceHeartbeatTimer = timer
    }
    
    func removeDevice(showId: String, deviceUUID: UUID) {
        let topic = "shows/\(showId)/devices/\(deviceUUID.uuidString)"
        
        deviceHeartbeatTimer?.cancel()
        deviceHeartbeatTimer = nil
        
        sendData(to: topic, message: "offline")
    }
    
    func stopBroadcastingDevice() {
        deviceHeartbeatTimer?.cancel()
        deviceHeartbeatTimer = nil
    }
    
    private func startPeriodicUpdate(for id: String) {
        updateTimers[id]?.cancel()
        
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + 60, repeating: 60)
        timer.setEventHandler { [weak self] in
            self?.sendData(to: "shows/\(id)", message: "updated")
        }
        timer.resume()
        
        updateTimers[id] = timer
    }
    
    func stopPeriodicUpdate(for id: String) {
        updateTimers[id]?.cancel()
        updateTimers.removeValue(forKey: id)
    }
}
