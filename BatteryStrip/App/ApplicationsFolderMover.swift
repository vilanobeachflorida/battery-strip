import AppKit
import Darwin

/// Offers to move the app into Applications when it's opened from somewhere else, like the Downloads
/// folder or the disk image. Opening at login and the Low Power Mode helper both need it to stay put.
enum ApplicationsFolderMover {
    /// Returns true when the app is moving and this copy is about to quit.
    static func offerIfNeeded() -> Bool {
        #if DEBUG
        // Development builds run from the build folder.
        return false
        #else
        let source = Bundle.main.bundleURL
        guard !isInApplicationsFolder(source) else { return false }

        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Move Battery Strip to Applications?"
        alert.informativeText = "Battery Strip needs to be in your Applications folder to open at login and keep working after you restart."
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            let destination = try move(source)
            relaunch(destination)
            return true
        } catch {
            let failure = NSAlert()
            failure.messageText = "Battery Strip couldn't move itself"
            failure.informativeText = "Drag it into the Applications folder in Finder, then open it from there.\n\n\(error.localizedDescription)"
            failure.runModal()
            return false
        }
        #endif
    }

    private static func isInApplicationsFolder(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        return applicationsFolders().contains { path.hasPrefix($0.path + "/") }
    }

    private static func applicationsFolders() -> [URL] {
        [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications")]
    }

    private static func move(_ source: URL) throws -> URL {
        let fileManager = FileManager.default
        // Without admin rights /Applications may not be writable; the personal Applications folder always is.
        var folder = URL(fileURLWithPath: "/Applications")
        if !fileManager.isWritableFile(atPath: folder.path) {
            folder = fileManager.homeDirectoryForCurrentUser.appending(path: "Applications")
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let destination = folder.appending(path: source.lastPathComponent)
        if fileManager.fileExists(atPath: destination.path) {
            // An older copy goes to the Trash rather than being deleted outright.
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.copyItem(at: source, to: destination)
        // The copy keeps the download's quarantine flag, which would make macOS run it from a
        // temporary location again. The person has already chosen to open it.
        removeQuarantine(from: destination)

        // Tidy up a plain download. A copy on the disk image, or one macOS is running from a
        // temporary location, can't be removed and doesn't need to be.
        let path = source.path
        if !path.hasPrefix("/Volumes/"), !path.contains("/AppTranslocation/") {
            try? fileManager.trashItem(at: source, resultingItemURL: nil)
        }
        return destination
    }

    private static func removeQuarantine(from bundle: URL) {
        removexattr(bundle.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        guard let items = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: nil) else { return }
        for case let item as URL in items {
            removexattr(item.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        }
    }

    private static func relaunch(_ app: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
