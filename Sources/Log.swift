import Foundation

// Diagnostic logging — off by default, enabled per-machine via:
//   defaults write cc.jorviksoftware.BrowserCommander debugLogging -bool YES
//   defaults delete cc.jorviksoftware.BrowserCommander debugLogging   # turn off
// When on, timestamped lines are appended to
//   ~/Library/Logs/Browser Commander/browsercommander.log
// and the run before the last rotation is kept in browsercommander.log.1.
//
// Never write to Console/stderr or /tmp. This mirrors the Jorvik logging convention: a
// symlink-safe append to a 0700 directory, gated behind a UserDefaults flag read on every
// call. The log stays on this Mac, is private to this user, and is never written unless the
// user turns it on.
//
// It never records a page's full address: navigation lines carry the browser, the
// process and the host only.
private let bcLogDirectory: URL = FileManager.default
    .urls(for: .libraryDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Logs", isDirectory: true)
    .appendingPathComponent("Browser Commander", isDirectory: true)
private let bcLogPath = bcLogDirectory.appendingPathComponent("browsercommander.log").path
private let bcPreviousLogPath = bcLogDirectory.appendingPathComponent("browsercommander.log.1").path

private let bcLogQueue = DispatchQueue(label: "cc.jorviksoftware.BrowserCommander.log")
private let bcLogFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f
}()

/// Rotate once the live log passes this many bytes, keeping one previous generation, so
/// the logs can never occupy more than twice this figure.
///
/// 4 MB by default, as in MenuTidy, which added rotation on 2026-09-20. A navigation
/// writes one line of about 100 bytes, so 4 MB holds tens of thousands. A knob, because a
/// long tuning session may want more:
///
///     defaults write cc.jorviksoftware.BrowserCommander debugLogMaxBytes -int 20971520
private var bcLogMaxBytes: Int {
    let stored = UserDefaults.standard.integer(forKey: "debugLogMaxBytes")
    return stored > 0 ? stored : 4 * 1024 * 1024
}

/// Takes its message as an autoclosure, so a disabled call builds no string.
func bcLog(_ msg: @autoclosure () -> String) {
    guard UserDefaults.standard.bool(forKey: "debugLogging") else { return }
    let line = "\(bcLogFmt.string(from: Date()))  \(msg())\n"
    let limit = bcLogMaxBytes
    bcLogQueue.async {
        bcAppend(line)
        // One process and one serial queue write this file, so the size read here is
        // the file just written to, and nothing can rotate it in between. MenuTidy also
        // follows the inode, because two of its processes share one log; this app has no
        // second writer to follow.
        var info = stat()
        guard stat(bcLogPath, &info) == 0, info.st_size >= limit else { return }
        unlink(bcPreviousLogPath)
        guard rename(bcLogPath, bcPreviousLogPath) == 0 else { return }
        bcAppend("\(bcLogFmt.string(from: Date()))  log rotated at \(info.st_size) bytes; the run before this is in browsercommander.log.1\n")
    }
}

/// Appends one line. Runs on `bcLogQueue` only.
private func bcAppend(_ line: String) {
    guard let data = line.data(using: .utf8) else { return }
    try? FileManager.default.createDirectory(at: bcLogDirectory, withIntermediateDirectories: true,
                                             attributes: [.posixPermissions: 0o700])
    // O_NOFOLLOW + 0700 parent dir closes the symlink-attack vector.
    let fd = open(bcLogPath, O_WRONLY | O_APPEND | O_CREAT | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { return }
    defer { close(fd) }
    data.withUnsafeBytes { _ = write(fd, $0.baseAddress, $0.count) }
}
