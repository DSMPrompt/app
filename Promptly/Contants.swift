//
//  Contants.swift
//  Promptly
//
//  Created by Sasha Bagrov on 01/10/2025.
//

import Foundation

struct Constants {
    private static let mqttIPKey = "mqttIP"
    private static let mqttPortKey = "mqttPort"
    
    static var mqttIP: String {
        get {
            UserDefaults.standard.string(forKey: mqttIPKey) ?? "192.168.1.1"
        }
        set {
            UserDefaults.standard.set(newValue, forKey: mqttIPKey)
        }
    }
    
    static var mqttPort: Int {
        get {
            let port = UserDefaults.standard.integer(forKey: mqttPortKey)
            return port == 0 ? 1883 : port
        }
        set {
            UserDefaults.standard.set(newValue, forKey: mqttPortKey)
        }
    }
}
