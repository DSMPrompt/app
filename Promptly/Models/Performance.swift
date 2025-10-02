//
//  Peformance.swift
//  Promptly
//
//  Created by Sasha Bagrov on 04/06/2025.
//

import Foundation
import SwiftData

@Model
class Performance: Identifiable {
    var id: UUID
    
    var date: Date
    var calls: [PerformanceCall]
    var timing: PerformanceTiming?
    var show: Show?
    
    init(id: UUID, date: Date, calls: [PerformanceCall], timing: PerformanceTiming? = nil, show: Show? = nil) {
        self.id = id
        self.date = date
        self.calls = calls
        self.timing = timing
        self.show = show
    }
}

@Model
class PerformanceCall: Identifiable {
    var id: UUID
    
    var title: String
    
    var call: CallType
    
    init(id: UUID, title: String, call: CallType) {
        self.id = id
        self.title = title
        self.call = call
    }
}


enum PreShowCall: Codable {
    case half, quarter, five, beginners, places
}

enum IntervalCall: Codable {
    case half, quarter, five, beginners
}


@Model
class PerformanceTiming: Identifiable {
    var id = UUID()
    var curtainTime: Date
    
    // House management
    var houseOpenTime: Date?
    var houseOpenPlanned: Date? // When you planned to open
    var clearanceTime: Date?    // When stage is clear for actors
    
    // Act structure
    var acts: [Act] = []
    var intervals: [Interval] = []
    
    // Call settings
    var callSettings: CallSettings
    
    // Performance state
    var currentState: PerformanceState
    var startTime: Date?
    var endTime: Date?
    
    // Timing records
    var actTimings: [ActTiming] = []
    var showStops: [ShowStop] = []
    
    init(id: UUID = UUID(), curtainTime: Date, houseOpenTime: Date? = nil, houseOpenPlanned: Date? = nil, clearanceTime: Date? = nil, acts: [Act], intervals: [Interval], callSettings: CallSettings, currentState: PerformanceState, startTime: Date? = nil, endTime: Date? = nil, actTimings: [ActTiming], showStops: [ShowStop]) {
        self.id = id
        self.curtainTime = curtainTime
        self.houseOpenTime = houseOpenTime
        self.houseOpenPlanned = houseOpenPlanned
        self.clearanceTime = clearanceTime
        self.acts = acts
        self.intervals = intervals
        self.callSettings = callSettings
        self.currentState = currentState
        self.startTime = startTime
        self.endTime = endTime
        self.actTimings = actTimings
        self.showStops = showStops
    }
}

@Model
class Act {
    var id = UUID()
    var number: Int
    var name: String
    var startTime: Date?
    var endTime: Date?
    var includeInRunningTime: Bool = true
    
    init(number: Int, name: String) {
        self.number = number
        self.name = name
    }
}

@Model
class Interval {
    var id = UUID()
    var number: Int
    var name: String = "Interval"
    var plannedDuration: TimeInterval
    var actualDuration: TimeInterval?
    var startTime: Date?
    var endTime: Date?
    
    init(number: Int, plannedDuration: TimeInterval) {
        self.number = number
        self.plannedDuration = plannedDuration
    }
}

@Model
class ActTiming {
    var id = UUID()
    var actNumber: Int
    var startTime: Date
    var endTime: Date?
    var duration: TimeInterval {
        guard let endTime = endTime else { return 0 }
        return endTime.timeIntervalSince(startTime)
    }
    
    init(actNumber: Int, startTime: Date) {
        self.actNumber = actNumber
        self.startTime = startTime
    }
}

@Model
class ShowStop {
    var id = UUID()
    var timestamp: Date
    var reason: String
    var duration: TimeInterval?
    var actNumber: Int
    
    init(timestamp: Date, reason: String, actNumber: Int) {
        self.timestamp = timestamp
        self.reason = reason
        self.actNumber = actNumber
    }
}

enum PerformanceState: Codable, Equatable {
    case preShow
    case houseOpen
    case clearance
    case inProgress(actNumber: Int)
    case interval(intervalNumber: Int)
    case completed
    case stopped
}

extension PerformanceState {
    init(displayName: String) {
        if displayName == "Pre-Show" {
            self = .preShow
        } else if displayName == "House Open" {
            self = .houseOpen
        } else if displayName == "Stage Clear" {
            self = .clearance
        } else if displayName.hasPrefix("Act ") && displayName.hasSuffix(" Running") {
            let numberString = displayName
                .dropFirst(4)
                .dropLast(8)
            if let actNumber = Int(numberString) {
                self = .inProgress(actNumber: actNumber)
            } else {
                self = .preShow
            }
        } else if displayName.hasPrefix("Interval ") {
            let numberString = displayName.dropFirst(9)
            if let intervalNumber = Int(numberString) {
                self = .interval(intervalNumber: intervalNumber)
            } else {
                self = .preShow
            }
        } else if displayName == "Show Complete" {
            self = .completed
        } else if displayName == "Show Stopped" {
            self = .stopped
        } else {
            self = .preShow
        }
    }
}

@Model
class CallSettings {
   var halfTime: TimeInterval = 35 * 60
   var quarterTime: TimeInterval = 20 * 60
   var fiveTime: TimeInterval = 10 * 60
   var beginnersTime: TimeInterval = 5 * 60
   var houseOpenOffset: TimeInterval = -30 * 60
   var clearanceOffset: TimeInterval = -10 * 60
   var enableSoundAlerts: Bool = true
   var customMessage: String = ""
   
   init(halfTime: TimeInterval = 35 * 60, quarterTime: TimeInterval = 20 * 60, fiveTime: TimeInterval = 10 * 60, beginnersTime: TimeInterval = 5 * 60, houseOpenOffset: TimeInterval = -30 * 60, clearanceOffset: TimeInterval = -10 * 60, enableSoundAlerts: Bool = true, customMessage: String = "") {
       self.halfTime = halfTime
       self.quarterTime = quarterTime
       self.fiveTime = fiveTime
       self.beginnersTime = beginnersTime
       self.houseOpenOffset = houseOpenOffset
       self.clearanceOffset = clearanceOffset
       self.enableSoundAlerts = enableSoundAlerts
       self.customMessage = customMessage
   }
}

enum CallType: Codable {
    case preShow(PreShowCall)
    case interval(IntervalCall)
    case houseManagement(HouseCall)
    case custom(Date)
}

enum HouseCall: Codable {
    case houseOpen
    case clearance
}

@Model
class PerformanceReport: Identifiable {
    var id = UUID()
    var performanceId: UUID
    var showTitle: String
    var performanceDate: Date
    var startTime: Date?
    var endTime: Date?
    var totalRuntime: TimeInterval
    var currentState: PerformanceState
    
    var callsExecuted: Int
    var cuesExecuted: Int
    var showStops: Int
    var emergencyStops: Int
    
    var callLogEntries: [ReportCallEntry] = []
    var cueExecutions: [ReportCueExecution] = []
    var showStopDetails: [ReportShowStop] = []
    
    var notes: String = ""
    var createdAt: Date
    
    init(
        performanceId: UUID,
        showTitle: String,
        performanceDate: Date,
        startTime: Date?,
        endTime: Date?,
        totalRuntime: TimeInterval,
        currentState: PerformanceState,
        callsExecuted: Int,
        cuesExecuted: Int,
        showStops: Int,
        emergencyStops: Int,
        callLogEntries: [CallLogEntry] = [],
        cueExecutions: [UUID] = [],
        showStopDetails: [ShowStop] = []
    ) {
        self.performanceId = performanceId
        self.showTitle = showTitle
        self.performanceDate = performanceDate
        self.startTime = startTime
        self.endTime = endTime
        self.totalRuntime = totalRuntime
        self.currentState = currentState
        self.callsExecuted = callsExecuted
        self.cuesExecuted = cuesExecuted
        self.showStops = showStops
        self.emergencyStops = emergencyStops
        self.createdAt = Date()
        
        self.callLogEntries = callLogEntries.map { entry in
            ReportCallEntry(
                timestamp: entry.timestamp,
                message: entry.message,
                type: "\(entry.type)"
            )
        }
        
        self.showStopDetails = showStopDetails.map { stop in
            ReportShowStop(
                timestamp: stop.timestamp,
                reason: stop.reason,
                duration: stop.duration ?? 0,
                actNumber: stop.actNumber
            )
        }
    }
}

@Model
class ReportCallEntry: Identifiable {
    var id = UUID()
    var timestamp: Date
    var message: String
    var type: String
    
    init(timestamp: Date, message: String, type: String) {
        self.timestamp = timestamp
        self.message = message
        self.type = type
    }
}

@Model
class ReportCueExecution: Identifiable {
    var id = UUID()
    var timestamp: Date
    var cueLabel: String
    var cueType: String
    var lineNumber: Int
    var executionMethod: String
    
    init(timestamp: Date, cueLabel: String, cueType: String, lineNumber: Int, executionMethod: String) {
        self.timestamp = timestamp
        self.cueLabel = cueLabel
        self.cueType = cueType
        self.lineNumber = lineNumber
        self.executionMethod = executionMethod
    }
}

@Model
class ReportShowStop: Identifiable {
    var id = UUID()
    var timestamp: Date
    var reason: String
    var duration: TimeInterval
    var actNumber: Int
    
    init(timestamp: Date, reason: String, duration: TimeInterval, actNumber: Int) {
        self.timestamp = timestamp
        self.reason = reason
        self.duration = duration
        self.actNumber = actNumber
    }
}
