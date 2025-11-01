import AppKit
import Foundation

// Security: These commands are allowlisted and validated to prevent command injection
// They contain no user input and use only read-only query operations
private let aerospaceGetAllWorkspaceCommand = "aerospace list-workspaces --all"
private let aerospaceGetFocusWorkspaceCommand = "aerospace list-workspaces --focused"
private let aerospaceGetAllAppsCommand =
    "aerospace list-windows --all --format \"%{workspace}|||%{app-bundle-id}|||%{app-name}\""

private let yabaiGetAllWorkspacesCommand = "yabai -m query --spaces"
private let yabaiGetAllAppsCommand = "yabai -m query --windows"

// Security: Allowlist of safe commands that can be executed
// These are read-only queries with no user input
private let allowedCommands: Set<String> = [
    aerospaceGetAllWorkspaceCommand,
    aerospaceGetFocusWorkspaceCommand,
    aerospaceGetAllAppsCommand,
    yabaiGetAllWorkspacesCommand,
    yabaiGetAllAppsCommand
]

private func getBundleIdentifier(for pid: pid_t) -> String? {
    let runningApps = NSWorkspace.shared.runningApplications

    if let app = runningApps.first(where: { $0.processIdentifier == pid }) {
        return app.bundleIdentifier
    }

    return nil
}

struct YabaiWorkspace: Codable {
    let index: Int
    let hasFocus: Bool

    enum CodingKeys: String, CodingKey {
        case index
        case hasFocus = "has-focus"
    }
}

struct YabaiApp: Codable {
    let pid: Int32
    let app: String
    let space: Int
    
    let hasAxReference: Bool

    enum CodingKeys: String, CodingKey {
        case pid
        case app
        case space
        case hasAxReference = "has-ax-reference"
    }
}

private func runShellCommand(_ command: String, arguments: [String] = []) -> String {
    // Security: Validate that the command is in our allowlist
    guard allowedCommands.contains(command) else {
        print("Error: Attempted to execute non-allowlisted command: \(command)")
        return ""
    }

    // Security: Reject commands with additional arguments (defense in depth)
    guard arguments.isEmpty else {
        print("Error: Shell command arguments not supported for security reasons")
        return ""
    }

    let process = Process()
    process.launchPath = "/bin/sh"
    process.arguments = ["-c", "export PATH=\"/opt/homebrew/bin:$PATH\" && \(command)"]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
    } catch {
        print("Failed to run process: \(error)")
        return ""
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
}

func getAllWorkspaces(source: String) -> [String] {
    if source == "aerospace" {
        let result = runShellCommand(aerospaceGetAllWorkspaceCommand)
        return result.split(separator: "\n").map({ String($0) })
    } else if source == "yabai" {
        let result = runShellCommand(yabaiGetAllWorkspacesCommand)
        guard let jsonData = result.data(using: .utf8) else {
            fatalError("Failed to convert JSON string to data")
        }
        do {
            let decoder = JSONDecoder()
            let json = try decoder.decode([YabaiWorkspace].self, from: jsonData)
            return json.map({ String($0.index) }
            )
        } catch {
            fatalError("Failed to parse JSON: \(error)")
        }
    } else {
        return []
    }
}

func getFocusedWorkspace(source: String) -> String {
    if source == "aerospace" {
        let result = runShellCommand(aerospaceGetFocusWorkspaceCommand)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    } else if source == "yabai" {
        let result = runShellCommand(yabaiGetAllWorkspacesCommand)
        guard let jsonData = result.data(using: .utf8) else {
            fatalError("Failed to convert JSON string to data")
        }
        do {
            let decoder = JSONDecoder()
            let json = try decoder.decode([YabaiWorkspace].self, from: jsonData)
            return json.filter({ $0.hasFocus }).map({ String($0.index) })
                .first ?? ""
        } catch {
            fatalError("Failed to parse JSON: \(error)")
        }
    } else {
        return ""
    }
}

func getAllApps(source: String) -> [AppDataType] {
    if source == "aerospace" {
        var apps: [AppDataType] = []
        let result = runShellCommand(aerospaceGetAllAppsCommand)
        for appString in result.split(separator: "\n") {
            let appData = appString.components(separatedBy: "|||")
            guard appData.count == 3 else { continue }
            apps.append(
                AppDataType(
                    workspaceId: appData[0],
                    bundleId: appData[1],
                    appName: appData[2]
                )
            )
        }
        return apps
    } else if source == "yabai" {
        let result = runShellCommand(yabaiGetAllAppsCommand)
        guard let jsonData = result.data(using: .utf8) else { return [] }
        do {
            let decoder = JSONDecoder()
            let json = try decoder.decode([YabaiApp].self, from: jsonData)
            return json
                .filter({ $0.pid != ProcessInfo.processInfo.processIdentifier && $0.hasAxReference })
                .map({
                AppDataType(
                    workspaceId: String($0.space),
                    bundleId: getBundleIdentifier(for: $0.pid) ?? "",
                    appName: $0.app)
            })
        } catch {
            fatalError("Failed to parse JSON: \(error)")
        }
    } else {
        return []
    }
}
