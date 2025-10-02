//
//  JSONServer.swift
//  Promptly
//
//  Created by Sasha Bagrov on 01/10/2025.
//

import Network
import Foundation
import Combine

class JSONServer: ObservableObject {
    let port: NWEndpoint.Port
    let listener: NWListener
    var connections: [NWConnection] = []
    
    init(port: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
        self.listener = try! NWListener(using: .tcp, on: self.port)
    }
    
    func start(dataToServe: [String: Any]) {
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Server ready on port \(self.port)")
            case .failed(let error):
                print("Server failed: \(error)")
            default:
                break
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection, data: dataToServe)
        }
        
        listener.start(queue: .main)
    }
    
    func stop() {
        listener.cancel()
        connections.forEach { $0.cancel() }
    }
    
    private func handleConnection(_ connection: NWConnection, data: [String: Any]) {
        connections.append(connection)
        
        connection.start(queue: .main)
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, context, isComplete, error in
            if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) {
                let response = self?.buildHTTPResponse(body: jsonData)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }
    
    private func buildHTTPResponse(body: Data) -> Data {
        let header = """
        HTTP/1.1 200 OK\r
        Content-Type: application/json\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r
        
        """
        var response = header.data(using: .utf8)!
        response.append(body)
        return response
    }
}
