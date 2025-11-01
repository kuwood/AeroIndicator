import Foundation

class Socket {
    private let socketPath = "/tmp/AeroIndicator"
    private var fd: Int32 = -1
    private var running = true
    private var messageHandler: ((String) -> Void)?
    private var isClient = false

    init(isClient: Bool = false, messageHandler: ((String) -> Void)? = nil) {
        self.isClient = isClient
        self.messageHandler = messageHandler
        setupSocket()
    }

    private func setupSocket() {
        if !isClient {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            close(fd)
            fatalError("Error creating socket: \(String(cString: strerror(errno)))")
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        strcpy(&address.sun_path.0, socketPath)

        let addrSize = socklen_t(
            MemoryLayout<sockaddr_un>.size(ofValue: address)
        )

        if isClient {
            let connectResult = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, addrSize)
                }
            }

            if connectResult != 0 {
                print("Connect failed: \(String(cString: strerror(errno)))")
                close(fd)
                exit(1)
            }
        } else {
            try? FileManager.default.removeItem(atPath: socketPath)

            let bindResult = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, addrSize)
                }
            }

            guard bindResult == 0 else {
                close(fd)
                fatalError("Bind failed: \(String(cString: strerror(errno)))")
            }

            // Security: Set restrictive permissions on socket (owner read/write only)
            // This prevents other users from sending commands to this app
            do {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: socketPath
                )
            } catch {
                print("Warning: Could not set socket permissions: \(error)")
            }

            guard listen(fd, 5) != -1 else {
                close(fd)
                fatalError("Listen failed: \(String(cString: strerror(errno)))")
            }
        }
    }

    func send(message: String) {
        let messageData = message.data(using: .utf8)!

        let _ = messageData.withUnsafeBytes {
            write(self.fd, $0.baseAddress, messageData.count)
        }
    }

    func startListening() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }

            while self.running {
                let clientSocket = accept(self.fd, nil, nil)
                if clientSocket == -1 {
                    if errno == EINTR {
                        continue
                    }
                    print("Accept failed: \(String(cString: strerror(errno)))")
                    break
                }
                self.handleClient(clientSocket: clientSocket)
            }

            self.cleanup()
        }
    }

    private func handleClient(clientSocket: Int32) {
        var buffer = [UInt8](repeating: 0, count: 1024)
        let bytesRead = read(clientSocket, &buffer, buffer.count)
        if bytesRead > 0 {
            let data = Data(bytes: buffer, count: bytesRead)
            if let message = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async { [weak self] in
                    self?.messageHandler?(message)
                }
            }
        }
        close(clientSocket)
    }

    func stop() {
        running = false
        cleanup()
    }

    private func cleanup() {
        if fd != -1 {
            close(fd)
            fd = -1
        }
        if !isClient {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
    }

    deinit {
        stop()
    }
}
