//
//  Script.swift
//  Promptly
//
//  Created by Sasha Bagrov on 04/06/2025.
//

import Foundation
import SwiftData
import SwiftUI

@Model
class Script: Identifiable {
    var id: UUID
    var name: String
    var dateAdded: Date
    @Relationship(deleteRule: .cascade) var lines: [ScriptLine] = []
    @Relationship(deleteRule: .cascade) var sections: [ScriptSection] = []
    
    init(id: UUID, name: String, dateAdded: Date, lines: [ScriptLine] = []) {
        self.id = id
        self.name = name
        self.dateAdded = dateAdded
        self.lines = lines
    }
}

@Model
class ScriptSection: Identifiable {
    var id: UUID
    var title: String
    var type: SectionType
    var startLineNumber: Int
    var endLineNumber: Int?
    var notes: String = ""
    
    init(id: UUID, title: String, type: SectionType, startLineNumber: Int) {
        self.id = id
        self.title = title
        self.type = type
        self.startLineNumber = startLineNumber
    }
}

enum SectionType: String, Codable, CaseIterable {
    case act = "act"
    case scene = "scene"
    case preset = "preset"
    case songNumber = "song_number"
    case custom = "custom"
    
    var displayName: String {
        switch self {
        case .act: return "Act"
        case .scene: return "Scene"
        case .preset: return "Preset/Set Change"
        case .songNumber: return "Song/Musical Number"
        case .custom: return "Custom"
        }
    }
    
    var color: String {
        switch self {
        case .act: return "#FF6B6B"      // Red
        case .scene: return "#4ECDC4"    // Teal
        case .preset: return "#45B7D1"   // Blue
        case .songNumber: return "#96CEB4" // Green
        case .custom: return "#FECA57"   // Yellow
        }
    }
}

@Model
class ScriptLine: Identifiable {
    var id: UUID
    var lineNumber: Int
    var content: String // Raw text content
    var flags: [ScriptLineFlags] = []
    @Relationship(deleteRule: .cascade) var elements: [LineElement] = []
    @Relationship(deleteRule: .cascade) var cues: [Cue] = []
    var isMarked: Bool = false
    var markColor: String? // Hex color for line marking
    var notes: String = ""
    
    init(id: UUID, lineNumber: Int, content: String, flags: [ScriptLineFlags]) {
        self.id = id
        self.lineNumber = lineNumber
        self.content = content
        self.flags = flags
        // Parse content after initialization
        DispatchQueue.main.async {
            self.parseContentIntoElements()
        }
    }
    
    // Parse the content into word/space elements
    func parseContentIntoElements() {
        elements.removeAll()
        let words = content.split(separator: " ", omittingEmptySubsequences: false)
        
        for (index, word) in words.enumerated() {
            let element = LineElement(
                id: UUID(),
                position: index,
                content: String(word),
                type: word.isEmpty ? .space : .word
            )
            elements.append(element)
        }
    }
    
    // Reconstruct content from elements
    func reconstructContent() -> String {
        return elements.sorted(by: { $0.position < $1.position })
            .map { $0.content }
            .joined(separator: " ")
    }
}

enum ScriptLineFlags: String, CaseIterable, Codable {
    case stageDirection = "stageDirection"
    case skip = "skip"
    
    var icon: String {
        switch self {
        case .stageDirection:
            return "theatermasks"
        case .skip:
            return "forward.fill"
        }
    }
    
    var label: String {
        switch self {
        case .stageDirection:
            return "Stage"
        case .skip:
            return "Skip"
        }
    }
    
    var color: Color {
        switch self {
        case .stageDirection:
            return .purple
        case .skip:
            return .red
        }
    }
}

@Model
class LineElement: Identifiable {
    var id: UUID
    var position: Int // Position within the line
    var content: String // The actual word or space
    var type: ElementType
    var isMarked: Bool = false
    var markColor: String? // Hex color for word marking
    
    init(id: UUID, position: Int, content: String, type: ElementType) {
        self.id = id
        self.position = position
        self.content = content
        self.type = type
    }
}

enum ElementType: String, Codable, CaseIterable {
    case word = "word"
    case space = "space"
    case punctuation = "punctuation"
}

@Model
class Cue: Identifiable {
    var id: UUID
    var lineId: UUID // Reference to the line
    var position: CuePosition // Where in the line this cue appears
    var type: CueType
    var label: String // e.g., "LX Q5 GO", "Sound Standby"
    var notes: String = ""
    var hasAlert: Bool = false
    var alertSound: String? // Sound file name for alert
    
    init(id: UUID, lineId: UUID, position: CuePosition, type: CueType, label: String) {
        self.id = id
        self.lineId = lineId
        self.position = position
        self.type = type
        self.label = label
    }
}

struct CuePosition: Codable {
    let elementIndex: Int // Which element (word) this cue comes after
    let offset: CueOffset // Before or after the element
}

enum CueOffset: String, Codable, CaseIterable {
    case before = "before"
    case after = "after"
}

enum CueType: String, Codable, CaseIterable {
    case lightingStandby = "lighting_standby"
    case lightingGo = "lighting_go"
    case soundStandby = "sound_standby"
    case soundGo = "sound_go"
    case flyStandby = "fly_standby"
    case flyGo = "fly_go"
    case automationStandby = "automation_standby"
    case automationGo = "automation_go"
    case setStandby = "set_standby"
    case setGo = "set_go"
    case cuelightStandby = "cuelight_standby"
    case cuelightGo = "cuelight_go"
    
    var displayName: String {
        switch self {
        case .lightingStandby: return "LX Standby"
        case .lightingGo: return "LX GO"
        case .soundStandby: return "SFX Standby"
        case .soundGo: return "SFX GO"
        case .flyStandby: return "Fly Standby"
        case .flyGo: return "Fly GO"
        case .automationStandby: return "Auto Standby"
        case .automationGo: return "Auto GO"
        case .setStandby: return "Set Standby"
        case .setGo: return "Set GO"
        case .cuelightStandby: return "Cuelight Standby"
        case .cuelightGo: return "Cuelight GO"
        }
    }
    
    var color: String {
        switch self {
        case .lightingStandby, .lightingGo: return "#FFD700"
        case .soundStandby, .soundGo: return "#FF6B6B"
        case .flyStandby, .flyGo: return "#4ECDC4"
        case .automationStandby, .automationGo: return "#45B7D1"
        case .setStandby, .setGo: return "#944ECD"
        case .cuelightStandby, .cuelightGo: return "#CD4EBC"
        }
    }
}

enum MarkColor: String, Codable, CaseIterable {
    case yellow = "#FFFF00"
    case pink = "#FF69B4"
    case green = "#90EE90"
    case blue = "#87CEEB"
    case orange = "#FFA500"
    case purple = "#DDA0DD"
    
    var displayName: String {
        switch self {
        case .yellow: return "Yellow"
        case .pink: return "Pink"
        case .green: return "Green"
        case .blue: return "Blue"
        case .orange: return "Orange"
        case .purple: return "Purple"
        }
    }
}

extension Script {
    func toDictionary() -> [String: Any] {
        return [
            "id": id.uuidString,
            "name": name,
            "dateAdded": ISO8601DateFormatter().string(from: dateAdded),
            "lines": lines.map { $0.toDictionary() },
            "sections": sections.map { $0.toDictionary() }
        ]
    }
}

extension ScriptSection {
    func toDictionary() -> [String: Any] {
        return [
            "id": id.uuidString,
            "title": title,
            "type": type.rawValue,
            "startLineNumber": startLineNumber,
            "endLineNumber": endLineNumber as Any,
            "notes": notes
        ]
    }
}

extension ScriptLine {
    func toDictionary() -> [String: Any] {
        return [
            "id": id.uuidString,
            "lineNumber": lineNumber,
            "content": content,
            "flags": flags.map { $0.rawValue }, // Convert enum cases to strings
            "elements": elements.map { $0.toDictionary() },
            "cues": cues.map { $0.toDictionary() },
            "isMarked": isMarked,
            "markColor": markColor as Any,
            "notes": notes
        ]
    }
}

extension LineElement {
    func toDictionary() -> [String: Any] {
        return [
            "id": id.uuidString,
            "position": position,
            "content": content,
            "type": type.rawValue,
            "isMarked": isMarked,
            "markColor": markColor as Any
        ]
    }
}

extension Cue {
    func toDictionary() -> [String: Any] {
        return [
            "id": id.uuidString,
            "lineId": lineId.uuidString,
            "position": [
                "elementIndex": position.elementIndex,
                "offset": position.offset.rawValue
            ],
            "type": type.rawValue,
            "label": label,
            "notes": notes,
            "hasAlert": hasAlert,
            "alertSound": alertSound as Any
        ]
    }
}

extension Script {
    convenience init?(from dict: [String: Any]) {
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = dict["name"] as? String,
              let dateAddedString = dict["dateAdded"] as? String,
              let dateAdded = ISO8601DateFormatter().date(from: dateAddedString) else {
            return nil
        }
        
        self.init(id: id, name: name, dateAdded: dateAdded)
        
        if let linesArray = dict["lines"] as? [[String: Any]] {
            self.lines = linesArray.compactMap { ScriptLine(from: $0) }
        }
        
        if let sectionsArray = dict["sections"] as? [[String: Any]] {
            self.sections = sectionsArray.compactMap { ScriptSection(from: $0) }
        }
    }
}

extension ScriptSection {
    convenience init?(from dict: [String: Any]) {
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let title = dict["title"] as? String,
              let typeString = dict["type"] as? String,
              let type = SectionType(rawValue: typeString),
              let startLineNumber = dict["startLineNumber"] as? Int else {
            return nil
        }
        
        self.init(id: id, title: title, type: type, startLineNumber: startLineNumber)
        
        self.endLineNumber = dict["endLineNumber"] as? Int
        self.notes = dict["notes"] as? String ?? ""
    }
}

extension ScriptLine {
    convenience init?(from dict: [String: Any]) {
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let lineNumber = dict["lineNumber"] as? Int,
              let content = dict["content"] as? String else {
            return nil
        }
        
        // Parse flags from dictionary
        var flags: [ScriptLineFlags] = []
        if let flagsArray = dict["flags"] as? [String] {
            flags = flagsArray.compactMap { ScriptLineFlags(rawValue: $0) }
        }
        
        self.init(id: id, lineNumber: lineNumber, content: content, flags: flags)
        
        if let elementsArray = dict["elements"] as? [[String: Any]] {
            self.elements = elementsArray.compactMap { LineElement(from: $0) }
        }
        
        if let cuesArray = dict["cues"] as? [[String: Any]] {
            self.cues = cuesArray.compactMap { Cue(from: $0) }
        }
        
        self.isMarked = dict["isMarked"] as? Bool ?? false
        self.markColor = dict["markColor"] as? String
        self.notes = dict["notes"] as? String ?? ""
    }
}

extension LineElement {
    convenience init?(from dict: [String: Any]) {
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let position = dict["position"] as? Int,
              let content = dict["content"] as? String,
              let typeString = dict["type"] as? String,
              let type = ElementType(rawValue: typeString) else {
            return nil
        }
        
        self.init(id: id, position: position, content: content, type: type)
        
        self.isMarked = dict["isMarked"] as? Bool ?? false
        self.markColor = dict["markColor"] as? String
    }
}

extension Cue {
    convenience init?(from dict: [String: Any]) {
        guard let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString),
              let lineIdString = dict["lineId"] as? String,
              let lineId = UUID(uuidString: lineIdString),
              let positionDict = dict["position"] as? [String: Any],
              let elementIndex = positionDict["elementIndex"] as? Int,
              let offsetString = positionDict["offset"] as? String,
              let offset = CueOffset(rawValue: offsetString),
              let typeString = dict["type"] as? String,
              let type = CueType(rawValue: typeString),
              let label = dict["label"] as? String else {
            return nil
        }
        
        let position = CuePosition(elementIndex: elementIndex, offset: offset)
        self.init(id: id, lineId: lineId, position: position, type: type, label: label)
        
        self.notes = dict["notes"] as? String ?? ""
        self.hasAlert = dict["hasAlert"] as? Bool ?? false
        self.alertSound = dict["alertSound"] as? String
    }
}

#if canImport(UIKit)
import UIKit

extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
#elseif canImport(AppKit)
import AppKit

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
#endif

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
