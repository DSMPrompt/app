//
//  BluetoothManager.swift
//  Promptly
//
//  Created by Sasha Bagrov on 05/06/2025.
//

import Foundation
import CoreBluetooth
import SwiftUI

class PromptlyBluetoothManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var discoveredDevices: [CBPeripheral] = []
    @Published var connectionStatus = "Disconnected"
    
    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var targetCharacteristic: CBCharacteristic?
    
    private let serviceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let characteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    
    var onButtonPress: ((String) -> Void)?
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            connectionStatus = "Bluetooth not available"
            print("🚫 Bluetooth not powered on: \(centralManager.state.rawValue)")
            return
        }
        
        discoveredDevices.removeAll()
        isScanning = true
        connectionStatus = "Scanning..."
        print("🔍 Starting BLE scan for service: \(serviceUUID)")
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.stopScanning()
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        if !isConnected {
            connectionStatus = discoveredDevices.isEmpty ? "No devices found" : "Select a device"
        }
    }
    
    func connect(to peripheral: CBPeripheral) {
        stopScanning()
        connectedPeripheral = peripheral
        peripheral.delegate = self
        connectionStatus = "Connecting..."
        centralManager.connect(peripheral, options: nil)
    }
    
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
    }
    
    func autoConnectToPromptlyClicker() {
        guard centralManager.state == .poweredOn else { return }
        
        let knownPeripherals = centralManager.retrieveConnectedPeripherals(withServices: [serviceUUID])
        
        if let promptlyDevice = knownPeripherals.first(where: { $0.name == "Promptly Clicker" }) {
            connect(to: promptlyDevice)
            return
        }
        
        startScanning()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if let promptlyDevice = self.discoveredDevices.first(where: { $0.name == "Promptly Clicker" }) {
                self.connect(to: promptlyDevice)
            }
        }
    }
}

extension PromptlyBluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        print("📡 Bluetooth state changed: \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            connectionStatus = "Ready"
            print("✅ Bluetooth powered on - auto-connecting...")
            autoConnectToPromptlyClicker()
        case .poweredOff:
            connectionStatus = "Bluetooth Off"
            print("🔴 Bluetooth powered off")
        case .resetting:
            connectionStatus = "Resetting"
            print("🔄 Bluetooth resetting")
        case .unauthorized:
            connectionStatus = "Unauthorized"
            print("🚫 Bluetooth unauthorized")
        case .unsupported:
            connectionStatus = "Unsupported"
            print("❌ Bluetooth unsupported")
        case .unknown:
            connectionStatus = "Unknown"
            print("❓ Bluetooth state unknown")
        @unknown default:
            connectionStatus = "Unknown State"
            print("❓ Bluetooth unknown state")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print("📱 Discovered device: \(peripheral.name ?? "Unknown") - \(peripheral.identifier)")
        print("   RSSI: \(RSSI) dB")
        print("   Advertisement data: \(advertisementData)")
        
        if !discoveredDevices.contains(peripheral) {
            discoveredDevices.append(peripheral)
        }
        
        if peripheral.name == "Promptly Clicker" && !isConnected {
            print("🎯 Found Promptly Clicker! Connecting...")
            connect(to: peripheral)
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        connectionStatus = "Connected to \(peripheral.name ?? "Unknown")"
        peripheral.discoverServices([serviceUUID])
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionStatus = "Failed to connect: \(error?.localizedDescription ?? "Unknown error")"
        connectedPeripheral = nil
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        connectionStatus = "Disconnected"
        connectedPeripheral = nil
        targetCharacteristic = nil
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.autoConnectToPromptlyClicker()
        }
    }
}

extension PromptlyBluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == serviceUUID {
                peripheral.discoverCharacteristics([characteristicUUID], for: service)
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == characteristicUUID {
                targetCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                connectionStatus = "Ready for remote control"
            }
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value,
              let value = String(data: data, encoding: .utf8) else {
            print("❌ Failed to read characteristic value")
            return
        }
        
        print("📥 Received: '\(value)' from Promptly Clicker")
        
        DispatchQueue.main.async {
            self.onButtonPress?(value)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if characteristic.isNotifying {
            connectionStatus = "Remote control active"
        }
    }
}

struct PromptlyBluetoothSettingsView: View {
    @ObservedObject var bluetoothManager: PromptlyBluetoothManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Promptly Clicker Status")
                        .font(.headline)

                    HStack {
                        Circle()
                            .fill(bluetoothManager.isConnected ? .green : .red)
                            .frame(width: 12, height: 12)

                        Text(bluetoothManager.connectionStatus)
                            .font(.subheadline)
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
                .cornerRadius(12)
                
                VStack(spacing: 16) {
                    if bluetoothManager.isConnected {
                        Button("Disconnect") {
                            bluetoothManager.disconnect()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    } else {
                        Button(bluetoothManager.isScanning ? "Scanning..." : "Scan for Devices") {
                            bluetoothManager.startScanning()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(bluetoothManager.isScanning)
                        
                        Button("Auto-Connect to Promptly Clicker") {
                            bluetoothManager.autoConnectToPromptlyClicker()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                if !bluetoothManager.discoveredDevices.isEmpty && !bluetoothManager.isConnected {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Available Devices")
                            .font(.headline)
                        
                        ForEach(bluetoothManager.discoveredDevices, id: \.identifier) { device in
                            Button(action: {
                                bluetoothManager.connect(to: device)
                            }) {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(device.name ?? "Unknown Device")
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        Text(device.identifier.uuidString)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("About Promptly Clicker")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The Promptly Clicker is a wireless remote with three buttons:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            Text("•")
                            Text("Pin 2 (NEXT): Navigate to next script line")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            Text("•")
                            Text("Pin 4 (PREV): Navigate to previous script line")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            Text("•")
                            Text("Pin 5 (CUE): Execute the next upcoming cue")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    
                    Text("Perfect for hands-free operation during live performances.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                .padding()
                #if os(iOS)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                #endif
                #if os(macOS)
                .background(Color(nsColor: .controlBackgroundColor))
                #endif
                .cornerRadius(12)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Bluetooth Remote")
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
