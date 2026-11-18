import AppKit
import Compression
import OSLog

/// Tab URLs for Firefox-family browsers, read from their session store.
///
/// Zen and Firefox expose a tab in the accessibility tree by title only — no
/// URL — so a tab whose URL holds the interesting word (a Terraform workspace
/// name, a PR number) cannot be found by it. The browser itself writes every
/// tab's title and URL to `sessionstore-backups/recovery.jsonlz4` every few
/// seconds; decoding it takes ~50 ms for 270 tabs, and the result is cached by
/// modification date.
enum BrowserSessions {

    /// Profiles directories per bundle identifier.
    private static let profileRoots: [String: String] = [
        "app.zen-browser.zen": "zen/Profiles",
        "org.mozilla.firefox": "Firefox/Profiles",
    ]

    static func supports(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier.map { profileRoots[$0] != nil } ?? false
    }

    /// URLs keyed by tab title, in session order. Titles repeat ("Sign out",
    /// "ADB Modern Authentication"), so each title maps to a queue.
    static func urlsByTitle(for bundleIdentifier: String) -> [String: [URL]] {

        guard let file = sessionFile(for: bundleIdentifier) else {
            return [:]
        }

        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[file], cached.modified == modified {
            return cached.urls
        }

        guard let urls = parse(file) else {
            return cache[file]?.urls ?? [:]
        }

        cache[file] = (modified, urls)
        return urls
    }

    // MARK: - Internals

    private static let lock = NSLock()
    private static var cache = [URL: (modified: Date?, urls: [String: [URL]])]()

    /// The most recently written session file among the browser's profiles.
    private static func sessionFile(for bundleIdentifier: String) -> URL? {

        guard let root = profileRoots[bundleIdentifier],
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }

        let profiles = support.appendingPathComponent(root)
        let candidates = ((try? FileManager.default.contentsOfDirectory(at: profiles, includingPropertiesForKeys: nil)) ?? [])
            .map { $0.appendingPathComponent("sessionstore-backups/recovery.jsonlz4") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        return candidates.max { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return left < right
        }
    }

    private static func parse(_ file: URL) -> [String: [URL]]? {

        let started = Date()

        guard let data = try? Data(contentsOf: file),
              let json = decodeMozLz4(data),
              let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let windows = root["windows"] as? [[String: Any]] else {
            OSLog.main.error("Palette: cannot read the session store at \(file.path, privacy: .private)")
            return nil
        }

        var urls = [String: [URL]]()

        for window in windows {
            for tab in window["tabs"] as? [[String: Any]] ?? [] {
                // `index` is 1-based and points at the tab's current history entry.
                let entries = tab["entries"] as? [[String: Any]] ?? []
                let index = (tab["index"] as? Int ?? entries.count) - 1
                guard entries.indices.contains(index),
                      let title = entries[index]["title"] as? String,
                      let address = entries[index]["url"] as? String,
                      let url = URL(string: address) else {
                    continue
                }
                urls[title, default: []].append(url)
            }
        }

        OSLog.main.log("Palette: read \(urls.values.reduce(0) { $0 + $1.count }) tab URL(s) from the session store in \(Int(Date().timeIntervalSince(started) * 1000)) ms")

        return urls
    }

    /// Mozilla's LZ4 container: "mozLz40\0", a little-endian UInt32 with the
    /// decompressed size, then one raw LZ4 block.
    private static func decodeMozLz4(_ data: Data) -> Data? {

        let magic = Data("mozLz40\0".utf8)

        guard data.count > 12, data.prefix(8) == magic else {
            return nil
        }

        let size = data.subdata(in: 8..<12).withUnsafeBytes { Int($0.loadUnaligned(as: UInt32.self).littleEndian) }
        let block = data.subdata(in: 12..<data.count)
        var output = Data(count: size)

        let written = output.withUnsafeMutableBytes { destination in
            block.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.baseAddress!.assumingMemoryBound(to: UInt8.self), size,
                    source.baseAddress!.assumingMemoryBound(to: UInt8.self), block.count,
                    nil, COMPRESSION_LZ4_RAW
                )
            }
        }

        return written == size ? output : nil
    }
}
