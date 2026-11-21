import AppKit
import UniformTypeIdentifiers

@MainActor
final class InstallerWindow: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 340),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
    private let gamePath = NSTextField(wrappingLabelWithString: "")
    private let installPath = NSTextField(wrappingLabelWithString: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let activity = NSProgressIndicator()
    private lazy var chooseGame = NSButton(title: "Choose Game Files…", target: self, action: #selector(selectGame))
    private lazy var chooseLocation = NSButton(title: "Change Install Location…", target: self, action: #selector(selectLocation))
    private lazy var installButton = NSButton(title: "Install Mod", target: self, action: #selector(startInstall))
    private lazy var revealButton = NSButton(title: "Show Game in Finder", target: self, action: #selector(revealGame))
    private var selection: URL?
    private var destination = Installation.defaultDestination
    private var installedApp: URL?
    private var installing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        window.title = "GTA Stephen Hawking Edition Installer"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.center()

        let title = NSTextField(labelWithString: "Install GTA Stephen Hawking Edition")
        title.font = .systemFont(ofSize: 25, weight: .bold)
        let help = NSTextField(wrappingLabelWithString: "Use your own classic Vice City game files. The installer downloads the mod and puts a playable copy in your Applications folder.")
        help.font = .systemFont(ofSize: 13)
        help.textColor = .secondaryLabelColor

        let sourceLabel = NSTextField(labelWithString: "Classic Vice City files")
        let destinationLabel = NSTextField(labelWithString: "Install location")
        for label in [sourceLabel, destinationLabel] { label.font = .systemFont(ofSize: 13, weight: .semibold) }
        for path in [gamePath, installPath] {
            path.font = .systemFont(ofSize: 12)
            path.textColor = .secondaryLabelColor
            path.isSelectable = true
            path.maximumNumberOfLines = 2
            path.lineBreakMode = .byTruncatingMiddle
        }

        let sourceRow = horizontal(path: gamePath, button: chooseGame)
        let destinationRow = horizontal(path: installPath, button: chooseLocation)
        status.font = .systemFont(ofSize: 13)
        status.isSelectable = true
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        activity.style = .spinning
        activity.controlSize = .small
        activity.isDisplayedWhenStopped = false
        installButton.keyEquivalent = "\r"
        window.defaultButtonCell = installButton.cell as? NSButtonCell
        revealButton.isHidden = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actions = NSStackView(views: [activity, status, spacer, revealButton, installButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 9

        let panel = NSStackView(views: [title, help, sourceLabel, sourceRow,
                                       destinationLabel, destinationRow, NSBox(), actions])
        panel.orientation = .vertical
        panel.alignment = .leading
        panel.spacing = 10
        panel.setCustomSpacing(21, after: help)
        panel.setCustomSpacing(17, after: sourceRow)
        panel.setCustomSpacing(18, after: destinationRow)
        panel.translatesAutoresizingMaskIntoConstraints = false

        guard let content = window.contentView else { return }
        content.addSubview(panel)
        for row in [help, sourceRow, destinationRow, actions] {
            row.widthAnchor.constraint(equalTo: panel.widthAnchor).isActive = true
        }
        if let divider = panel.arrangedSubviews.compactMap({ $0 as? NSBox }).first {
            divider.boxType = .separator
            divider.widthAnchor.constraint(equalTo: panel.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            panel.topAnchor.constraint(equalTo: content.topAnchor, constant: 25),
            panel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 25),
            panel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -25),
            panel.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -24)
        ])

        let homeApp = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Grand Theft Auto Vice City.app")
        selection = [Installation.defaultBase, homeApp].first { Installation.gameData(in: $0) != nil }
        refreshPaths()
        if FileManager.default.fileExists(atPath: destination.path) {
            let app = destination.appendingPathComponent(Installation.edition + ".app")
            if FileManager.default.fileExists(atPath: app.path) {
                installedApp = app
                revealButton.isHidden = false
                status.stringValue = "The game is already installed here."
            }
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func horizontal(path: NSTextField, button: NSButton) -> NSStackView {
        path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        path.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [path, button])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func refreshPaths() {
        gamePath.stringValue = selection.map { ($0.path as NSString).abbreviatingWithTildeInPath }
            ?? "Choose a macVC app or a GameData folder."
        installPath.stringValue = (destination.path as NSString).abbreviatingWithTildeInPath
        installButton.isEnabled = selection != nil && !installing
    }

    @objc private func selectGame() {
        let picker = NSOpenPanel()
        picker.title = "Choose Classic Vice City Files"
        picker.prompt = "Choose"
        picker.canChooseFiles = true
        picker.canChooseDirectories = true
        picker.allowedContentTypes = [.applicationBundle, .folder]
        picker.treatsFilePackagesAsDirectories = false
        picker.directoryURL = selection?.deletingLastPathComponent()
            ?? Installation.defaultBase.deletingLastPathComponent()
        picker.beginSheetModal(for: window) { response in
            guard response == .OK, let selected = picker.url else { return }
            guard Installation.gameData(in: selected) != nil else {
                self.showError("Choose a macVC app or a GameData folder containing the data and models folders.")
                return
            }
            self.selection = selected
            self.status.stringValue = ""
            self.refreshPaths()
        }
    }

    @objc private func selectLocation() {
        let picker = NSOpenPanel()
        picker.title = "Choose Where to Install the Mod"
        picker.prompt = "Choose"
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.canCreateDirectories = true
        picker.beginSheetModal(for: window) { response in
            guard response == .OK, let folder = picker.url else { return }
            self.destination = folder.appendingPathComponent(Installation.edition)
            self.status.stringValue = ""
            self.refreshPaths()
        }
    }

    @objc private func startInstall() {
        guard let selection, !installing else { return }
        let destination = self.destination
        installing = true
        chooseGame.isEnabled = false
        chooseLocation.isEnabled = false
        revealButton.isHidden = true
        refreshPaths()
        activity.startAnimation(nil)
        status.stringValue = "Preparing the installer…"

        Task.detached(priority: .userInitiated) {
            do {
                let installation = try Installation()
                let app = try await installation.install(base: selection, at: destination) { message in
                    DispatchQueue.main.async { self.status.stringValue = message }
                }
                await self.finishInstallation(app: app)
            } catch {
                await self.finishInstallation(error: error.localizedDescription)
            }
        }
    }

    private func finishInstallation(app: URL? = nil, error: String? = nil) {
        installing = false
        chooseGame.isEnabled = true
        chooseLocation.isEnabled = true
        activity.stopAnimation(nil)
        refreshPaths()
        if let app {
            installedApp = app
            status.stringValue = "Installation complete."
        }
        revealButton.isHidden = installedApp == nil
        if let error {
            status.stringValue = "Installation stopped."
            showError(error)
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t install the mod"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window)
    }

    @objc private func revealGame() {
        guard let app = installedApp else { return }
        NSWorkspace.shared.activateFileViewerSelecting([app])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !installing }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        installing ? .terminateCancel : .terminateNow
    }
}

@main
@MainActor
struct InstallerMain {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        if arguments.first == "--verify-install", arguments.count == 4 {
            let inputs = Array(arguments.dropFirst())
            Task.detached {
                do {
                    let app = try await Installation().install(
                        base: URL(fileURLWithPath: inputs[0]),
                        at: URL(fileURLWithPath: inputs[2]),
                        from: inputs[1] == "--download" ? nil : URL(fileURLWithPath: inputs[1])
                    ) { message in print(message) }
                    print("Installed \(app.path)")
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
                    exit(1)
                }
            }
            dispatchMain()
        }

        let application = NSApplication.shared
        let delegate = InstallerWindow()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        let menuBar = NSMenu()
        let appItem = NSMenuItem()
        menuBar.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Installer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        application.mainMenu = menuBar
        withExtendedLifetime(delegate) { application.run() }
    }
}
