import Foundation
import Network

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let portFile = URL(fileURLWithPath: CommandLine.arguments[2])
let interrupted = CommandLine.arguments[3] == "interrupted"
let parameters = NWParameters.tcp
parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
let listener = try NWListener(using: parameters)
listener.stateUpdateHandler = { state in
    if case .ready = state, let port = listener.port {
        try! Data(String(port.rawValue).utf8).write(to: portFile)
    }
}
listener.newConnectionHandler = { connection in
    connection.start(queue: .global())
    connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
        guard let data, let request = String(data: data, encoding: .utf8),
              let path = request.split(separator: " ").dropFirst().first,
              ["/appcast.xml", "/update.zip"].contains(String(path)),
              let body = try? Data(contentsOf: root.appendingPathComponent(String(path.dropFirst()))) else {
            connection.cancel(); return
        }
        let header = Data("HTTP/1.1 200 OK\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        let bytes = interrupted && path == "/update.zip" ? body.prefix(body.count / 2) : body[...]
        connection.send(content: header + bytes, completion: .contentProcessed { _ in connection.cancel() })
    }
}
listener.start(queue: .global())
dispatchMain()
