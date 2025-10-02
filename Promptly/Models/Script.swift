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
    @Relationship(deleteRule: .cascade) var elements: [LineElement] = []
    @Relationship(deleteRule: .cascade) var cues: [Cue] = []
    var isMarked: Bool = false
    var markColor: String? // Hex color for line marking
    var notes: String = ""
    
    init(id: UUID, lineNumber: Int, content: String) {
        self.id = id
        self.lineNumber = lineNumber
        self.content = content
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

enum StageLocation: String, Codable, CaseIterable {
    case pit = "pit"
    case leftWing = "left_wing"
    case rightWing = "right_wing"
    case upstage = "upstage"
    case downstage = "downstage"
    case stageLeft = "stage_left"
    case stageRight = "stage_right"
    case upstageLeft = "upstage_left"
    case upstageRight = "upstage_right"
    case downstageLeft = "downstage_left"
    case downstageRight = "downstage_right"
    case centerStage = "center_stage"
    
}

struct CueHapticConfig: Codable {
    var location: StageLocation // where are they (if someone is away used for quick swapping)
    var crewId: Int // unique id (goes from 0, 1, 2 etc) for the crew member, regardless of position
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
    case setWarning = "set_warning"
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
        case .setWarning: return "Set Warning"
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
        case .setStandby, .setGo, .setWarning: return "#944ECD"
        case .cuelightStandby, .cuelightGo: return "#CD4EBC"
        }
    }

    var cueStackColor: String {
        switch self {
            case .lightingStandby, .soundStandby, .flyStandby, .automationStandby, .setStandby, .setWarning, .cuelightStandby: return Color.orange
            case .lightingGo, .soundGo, .flyGo, .automationGo, .setGo, .cuelightGo: return Color.green
        }
    }

    var generalName: String {
        switch self {
            case .lightingStandby, .soundStandby, .flyStandby, .automationStandby, .setStandby, .cuelightStandby: return "STANDBY"
            case .lightingGo, .soundGo, .flyGo, .automationGo, .setGo, .cuelightGo: return "GO"
            case .setWarning: return "WARNING"
        }
    }

    var canHaptic: Bool {
        switch self {
            case .lightingStandby, .soundStandby, .flyStandby, .automationStandby, .cuelightStandby, .lightingGo, .soundGo, .flyGo, .automationGo, .cuelightGo: return false
            case .setWarning, .setStandby, .setGo: return true
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
