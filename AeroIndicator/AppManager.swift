import SwiftUI

class AppManager: ObservableObject {
    private var show = false
    private var window: MainWindow<AeroIndicatorApp>?
    private var server: Socket?

    @Published var workspaces: [String] = []
    @Published var focusWorkspace: String = ""
    @Published var allApps: [AppDataType] = []
    @Published var config: AeroConfig = readConfig()

    var isUpdatingApps = false

    func start() {
        Task {
            let workspace = getAllWorkspaces(source: config.source)
            let focusWorkspace = getFocusedWorkspace(source: config.source)
            let allApps = getAllApps(source: config.source)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.workspaces = workspace
                self.focusWorkspace = focusWorkspace
                self.allApps = allApps

                self.createWindow()
            }
        }
        startListeningKey()
        startListeningCommand()
    }

    private func createWindow() {
        guard let screenFrame = NSScreen.main?.frame else { return }
        let statusBarHeight = NSStatusBar.system.thickness
        let contentRect = NSRect(
            x: 0,
            y: 0,
            width: screenFrame.size.width,
            height: screenFrame.size.height - statusBarHeight
        )

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window = MainWindow(contentRect: contentRect) {
                AeroIndicatorApp(model: self)
            }

            self.window?.orderOut(nil)
        }
    }

    private func startListeningCommand() {
        server = Socket(isClient: false) { message in
            // Security: Validate and sanitize input
            let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)

            // Reject messages that are too long (DOS protection)
            guard trimmedMessage.count > 0 && trimmedMessage.count < 1000 else { return }

            let splitMessages = trimmedMessage.split(separator: " ").map({ String($0) })
            guard splitMessages.count > 0 else { return }

            // Security: Only allow specific commands (allowlist approach)
            let validCommands = ["workspace-change", "focus-change", "workspace-created-or-destroyed"]
            guard validCommands.contains(splitMessages[0]) else {
                print("Warning: Rejected invalid command: \(splitMessages[0])")
                return
            }

            if splitMessages[0] == "workspace-change" && splitMessages.count == 2 {
                // Security: Validate workspace name (alphanumeric and basic chars only)
                let workspace = splitMessages[1]
                let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
                guard workspace.rangeOfCharacter(from: allowedCharacters.inverted) == nil else {
                    print("Warning: Rejected invalid workspace name: \(workspace)")
                    return
                }

                withAnimation {
                    self.focusWorkspace = workspace
                }
            } else if splitMessages[0] == "focus-change" {
                self.getAllWorkspaceApps()
            } else if splitMessages[0] == "workspace-created-or-destroyed" {
                self.workspaces = getAllWorkspaces(source: self.config.source)
            }
        }
        server?.startListening()
    }

    private func getAllWorkspaceApps() {
        if self.isUpdatingApps { return }
        Task {
            self.isUpdatingApps = true
            let allApps = getAllApps(source: config.source)
            DispatchQueue.main.async {
                self.allApps = allApps
                self.isUpdatingApps = false
            }
        }
    }

    private func startListeningKey() {
        func handleEvent(_ event: NSEvent) {
            if event.modifierFlags.contains(.option) {
                self.show = true
                DispatchQueue.main.async {
                    self.window?.orderFrontRegardless()
                }
            } else if self.show {
                self.show = false
                DispatchQueue.main.async {
                    self.window?.orderOut(nil)
                }
            }
        }
        NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged],
            handler: { event in
                handleEvent(event)
            })

        NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged],
            handler: { event in
                handleEvent(event)
                return nil
            })
    }
}
