import CryptoKit
import Foundation

enum InstallationError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): return text
        }
    }
}

struct Manifest: Decodable {
    struct Operation: Decodable {
        enum Source: String, Decodable { case copy, literal }
        let source: Source
        let offset: UInt64
        let length: UInt64

        init(from decoder: Decoder) throws {
            var item = try decoder.unkeyedContainer()
            source = try item.decode(Source.self)
            offset = try item.decode(UInt64.self)
            length = try item.decode(UInt64.self)
        }
    }

    struct File: Decodable {
        enum Kind: String, Decodable { case base, new, diff, archive }
        let path: String
        let sha256: String
        let size: UInt64
        let kind: Kind
        let base: String?
        let baseSHA256: String?
        let member: String?
        let operations: [Operation]?

        enum CodingKeys: String, CodingKey {
            case path, sha256, size, kind, base, member, operations
            case baseSHA256 = "base_sha256"
        }
    }

    struct RuntimeFile: Decodable {
        let path: String
        let sha256: String
        let mode: Int
    }

    let version: Int
    let files: [File]
    let runtime: [RuntimeFile]
}

struct Installation {
    static let edition = "GTA Stephen Hawking Edition"
    static let defaultBase = URL(fileURLWithPath: "/Applications/Grand Theft Auto Vice City.app")
    static let defaultDestination = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Applications").appendingPathComponent(edition)
    private static let payloadName = "hawking-vice-city-macos-arm64.zip"
    private static let chunkSize = 1024 * 1024

    let playerURL: URL
    private let expectedDigest: String
    private let manifestBytes: Data
    private let manifest: Manifest
    private let fm = FileManager.default

    init(bundle: Bundle = .main) throws {
        guard let address = bundle.object(forInfoDictionaryKey: "HawkingPlayerURL") as? String,
              let url = URL(string: address), url.scheme == "https",
              let digest = bundle.object(forInfoDictionaryKey: "HawkingPlayerSHA256") as? String,
              let descriptor = bundle.url(forResource: "manifest", withExtension: "json") else {
            throw InstallationError.message("The installer is missing its configuration. Download a fresh copy.")
        }
        playerURL = url
        expectedDigest = digest
        manifestBytes = try Data(contentsOf: descriptor)
        manifest = try JSONDecoder().decode(Manifest.self, from: manifestBytes)
        guard manifest.version == 1 else {
            throw InstallationError.message("This installer does not recognize the game package format.")
        }
    }

    static func gameData(in selection: URL) -> URL? {
        let url = selection.resolvingSymlinksInPath()
        let data = url.pathExtension.lowercased() == "app"
            ? url.appendingPathComponent("Contents/Resources/GameData").resolvingSymlinksInPath() : url
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: data.path) else { return nil }
        let names = contents.map { $0.lowercased() }
        return names.contains("data") && names.contains("models") ? data : nil
    }

    func install(base selection: URL, at destination: URL, from localPlayerZIP: URL? = nil,
                 progress: @escaping @Sendable (String) -> Void) async throws -> URL {
        guard let base = Self.gameData(in: selection) else {
            throw InstallationError.message("Choose a macVC app or a classic Vice City GameData folder containing data and models.")
        }
        try requireNewDestination(destination)
        progress("Checking your classic Vice City files…")
        let originals = try checkOriginals(base)

        let scratch = destination.deletingLastPathComponent()
            .appendingPathComponent(".hawking-install-" + UUID().uuidString)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: scratch) }

        let playerZIP: URL
        if let localPlayerZIP {
            playerZIP = localPlayerZIP
        } else {
            progress("Downloading the mod files (633 MiB)…")
            let (download, response) = try await URLSession.shared.download(from: playerURL)
            defer { try? fm.removeItem(at: download) }
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw InstallationError.message("GitHub could not serve the game download. Try again in a moment.")
            }
            playerZIP = scratch.appendingPathComponent("player.zip")
            try fm.moveItem(at: download, to: playerZIP)
        }

        progress("Verifying and unpacking the download…")
        guard try digest(of: playerZIP) == expectedDigest else {
            throw InstallationError.message("The game download did not match its checksum. Try downloading it again.")
        }
        let player = scratch.appendingPathComponent("player")
        try run("/usr/bin/ditto", ["-x", "-k", playerZIP.path, player.path])
        if localPlayerZIP == nil { try fm.removeItem(at: playerZIP) }
        let payload = player.appendingPathComponent(playerURL.deletingPathExtension().lastPathComponent)
            .appendingPathComponent(Self.payloadName)
        let package = scratch.appendingPathComponent("package")
        try run("/usr/bin/ditto", ["-x", "-k", payload.path, package.path])
        try fm.removeItem(at: player)
        guard try Data(contentsOf: package.appendingPathComponent("manifest.json")) == manifestBytes else {
            throw InstallationError.message("The downloaded game package does not match the installer.")
        }

        let installation = scratch.appendingPathComponent("installation")
        let app = installation.appendingPathComponent(Self.edition + ".app")
        let data = installation.appendingPathComponent("GameData")
        progress("Assembling the mod and checking its game files…")
        try installRuntime(from: package, to: app)
        for file in manifest.files {
            try installFile(file, from: package, with: originals, to: data)
        }
        progress("Verifying the game app…")
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        try requireNewDestination(destination)
        try fm.moveItem(at: installation, to: destination)
        return destination.appendingPathComponent(Self.edition + ".app")
    }

    private func requireNewDestination(_ destination: URL) throws {
        if (try? fm.attributesOfItem(atPath: destination.path)) != nil {
            throw InstallationError.message("An installation already exists here. Choose a different install location to keep both copies.")
        }
    }

    private func checkOriginals(_ root: URL) throws -> [String: URL] {
        let files = try originalIndex(root)
        var results: [String: URL] = [:]
        var missing: [String] = []
        let expected = Set(manifest.files.compactMap(\.base)).sorted()
        let hashes = Dictionary(manifest.files.compactMap { file -> (String, String)? in
            guard let name = file.base, let hash = file.baseSHA256 else { return nil }
            return (name, hash)
        }, uniquingKeysWith: { first, _ in first })
        for name in expected {
            guard let path = files[name.lowercased()], let hash = hashes[name] else {
                missing.append(name)
                continue
            }
            let backup = path.appendingPathExtension("bak")
            for candidate in [path, backup] {
                let resolved = candidate.resolvingSymlinksInPath()
                if resolved.path.hasPrefix(root.path + "/"),
                   (try? resolved.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                   try digest(of: resolved) == hash {
                    results[name] = resolved
                    break
                }
            }
            if results[name] == nil { missing.append(name) }
        }
        if !missing.isEmpty {
            let sample = missing.prefix(5).joined(separator: ", ")
            throw InstallationError.message(
                "\(missing.count) base game file(s) are missing or differ. Choose a compatible macVC GameData folder. Examples: \(sample)."
            )
        }
        return results
    }

    private func originalIndex(_ root: URL) throws -> [String: URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let paths = fm.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: []) else {
            throw InstallationError.message("The selected game folder could not be read.")
        }
        var index: [String: URL] = [:]
        for case let path as URL in paths {
            let relative = String(path.path.dropFirst(root.path.count + 1))
            if relative.split(separator: "/").contains(where: {
                $0.hasPrefix(".") || $0.hasSuffix(".bak") || $0.hasSuffix(".blend1")
            }) {
                continue
            }
            let resolved = path.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(root.path + "/"),
                  try resolved.resourceValues(forKeys: keys).isRegularFile == true else { continue }
            if index.updateValue(path, forKey: relative.lowercased()) != nil {
                throw InstallationError.message("The selected game folder has conflicting file names: \(relative).")
            }
        }
        return index
    }

    private func installRuntime(from package: URL, to app: URL) throws {
        let runtime = package.appendingPathComponent("runtime")
        for file in manifest.runtime {
            guard file.path.hasPrefix("Contents/"), !file.path.hasPrefix("Contents/Resources/GameData/") else {
                throw InstallationError.message("The game package contains an invalid runtime path.")
            }
            let source = try relativeURL(file.path, in: runtime)
            let destination = try relativeURL(file.path, in: app)
            try verify(source, sha256: file.sha256)
            try copy(source, to: destination)
            try fm.setAttributes([.posixPermissions: file.mode & 0o777], ofItemAtPath: destination.path)
        }
    }

    private func installFile(_ file: Manifest.File, from package: URL, with originals: [String: URL],
                             to data: URL) throws {
        let destination = try relativeURL(file.path, in: data)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        switch file.kind {
        case .new:
            try copy(try patchMember(file, in: package), to: destination)
        case .base, .diff, .archive:
            guard let name = file.base, let base = originals[name] else {
                throw InstallationError.message("The game package is missing a base mapping for \(file.path).")
            }
            switch file.kind {
            case .base:
                try copy(base, to: destination)
            case .diff:
                try run("/usr/bin/bspatch", [base.path, destination.path, try patchMember(file, in: package).path])
            case .archive:
                try assembleArchive(file, original: base, changes: try patchMember(file, in: package), destination: destination)
            case .new:
                preconditionFailure("New files are handled above.")
            }
        }
        let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard size.map(UInt64.init) == file.size else {
            throw InstallationError.message("The installed size is incorrect for \(file.path).")
        }
        try verify(destination, sha256: file.sha256)
    }

    private func patchMember(_ file: Manifest.File, in package: URL) throws -> URL {
        guard let member = file.member, member.hasPrefix("patches/") else {
            throw InstallationError.message("The game package is missing the patch for \(file.path).")
        }
        return try relativeURL(member, in: package)
    }

    private func assembleArchive(_ file: Manifest.File, original: URL, changes: URL, destination: URL) throws {
        guard let operations = file.operations, fm.createFile(atPath: destination.path, contents: nil) else {
            throw InstallationError.message("Could not assemble \(file.path).")
        }
        let source = try FileHandle(forReadingFrom: original)
        let literals = try FileHandle(forReadingFrom: changes)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? source.close()
            try? literals.close()
            try? output.close()
        }
        var bytesLeft = file.size
        for operation in operations {
            guard operation.length > 0, operation.length <= bytesLeft else {
                throw InstallationError.message("Invalid archive patch for \(file.path).")
            }
            let input = operation.source == .copy ? source : literals
            try input.seek(toOffset: operation.offset)
            var remaining = operation.length
            bytesLeft -= remaining
            while remaining > 0 {
                guard let bytes = try input.read(upToCount: Int(min(remaining, UInt64(Self.chunkSize)))),
                      !bytes.isEmpty else {
                    throw InstallationError.message("An archive patch ended early for \(file.path).")
                }
                try output.write(contentsOf: bytes)
                remaining -= UInt64(bytes.count)
            }
        }
        guard bytesLeft == 0 else { throw InstallationError.message("Incomplete archive patch for \(file.path).") }
    }

    private func relativeURL(_ path: String, in root: URL) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.contains("\\"), !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw InstallationError.message("Invalid package path: \(path).")
        }
        return root.appendingPathComponent(path)
    }

    private func copy(_ source: URL, to destination: URL) throws {
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: destination)
    }

    private func verify(_ path: URL, sha256: String) throws {
        guard try digest(of: path) == sha256 else {
            throw InstallationError.message("A file failed its checksum: \(path.lastPathComponent).")
        }
    }

    private func digest(of path: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: path)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: Self.chunkSize), !data.isEmpty {
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func run(_ command: String, _ arguments: [String]) throws {
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: command)
        task.arguments = arguments
        task.standardOutput = output
        task.standardError = output
        try task.run()
        let details = output.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let text = String(decoding: details, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw InstallationError.message(text.isEmpty ? "\(command) failed." : text)
        }
    }
}
