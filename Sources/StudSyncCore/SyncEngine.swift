import Foundation
import CryptoKit
import Darwin

public actor SyncEngine {
    private struct Record: Codable {
        var revision: String
        var baselineHash: String?
        var incomingPath: String?
        var targetPath: String?
    }
    private struct Manifest: Codable {
        var records: [String: Record]
        var names: [String: [String: String]]
        var reservedPaths: Set<String>
    }
    private let manifest: URL
    private var records: [String: Record]
    private var names: [String: [String: String]] = [:]
    private var reservedPaths: Set<String> = []

    public init(manifest: URL) throws {
        self.manifest = manifest
        if FileManager.default.fileExists(atPath: manifest.path) {
            let data = try Data(contentsOf: manifest)
            if let saved = try? JSONDecoder().decode(Manifest.self, from: data) {
                records = saved.records; names = saved.names; reservedPaths = saved.reservedPaths
            } else { records = try JSONDecoder().decode([String: Record].self, from: data) }
        } else { records = [:] }
        // Preserve destinations from older manifests, which have no name assignments.
        for record in records.values {
            for path in [record.targetPath, record.incomingPath].compactMap({ $0 }) {
                var url = URL(fileURLWithPath: path).standardizedFileURL
                while url.path != "/" {
                    reservedPaths.insert(Self.folded(url.path))
                    url.deleteLastPathComponent()
                }
            }
        }
    }

    public static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let block = try handle.read(upToCount: 1_048_576), !block.isEmpty { hash.update(data: block) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public func synchronize(_ file: RemoteFile, courseID: String, root: URL,
                            fetch: @Sendable () async throws -> URL) async throws -> Change? {
        try Task.checkCancellation()
        let components = try localComponents(file, courseID: courseID, root: root)
        let target = try SafePath.destination(root: root, components: components)
        let key = root.standardizedFileURL.resolvingSymlinksInPath().path + "/" + courseID + "/" + file.id
        try migrateIDNamedFile(key: key, fileID: file.id, target: target, root: root, components: components)
        // A rename or older manifest cannot establish ownership of this destination.
        let old = records[key]?.targetPath == target.path ? records[key] : nil
        let manager = FileManager.default
        if old?.revision == file.revision, manager.fileExists(atPath: target.path) {
            if let path = old?.incomingPath {
                let incoming = URL(fileURLWithPath: path)
                if manager.fileExists(atPath: incoming.path) { return nil }
            } else { return nil }
        }
        let downloaded = try await fetch()
        defer { try? manager.removeItem(at: downloaded) }
        try Task.checkCancellation()
        let size = try downloaded.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard Int64(size ?? -1) == file.size else { throw StudSyncError.sizeMismatch }
        let remoteHash = try Self.hash(downloaded)
        _ = try SafePath.destination(root: root, components: components)
        let existingHash = manager.fileExists(atPath: target.path) ? try Self.hash(target) : nil
        if existingHash == remoteHash {
            records[key] = Record(revision: file.revision, baselineHash: remoteHash, incomingPath: nil, targetPath: target.path)
            try save()
            return nil
        }
        let conflict = existingHash != nil && (old?.baselineHash == nil || old?.baselineHash != existingHash)
        var destination = target
        if conflict {
            let name = try SafePath.suffixedComponent(target.lastPathComponent,
                suffix: " (StudIP \(UUID().uuidString.prefix(8)))", isFile: true)
            destination = target.deletingLastPathComponent().appendingPathComponent(name)
        }
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Validate again after creating directories; remote names may traverse existing symlinks.
        _ = try SafePath.destination(root: root, components: components)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".studsync-\(UUID().uuidString).part")
        defer { try? manager.removeItem(at: staging) }
        try manager.copyItem(at: downloaded, to: staging)
        if !conflict && manager.fileExists(atPath: destination.path) {
            _ = try manager.replaceItemAt(destination, withItemAt: staging)
        } else { try manager.moveItem(at: staging, to: destination) }
        reservedPaths.insert(Self.folded(destination.path))
        records[key] = Record(revision: file.revision,
                              baselineHash: conflict ? old?.baselineHash : remoteHash,
                              incomingPath: conflict ? destination.path : nil, targetPath: target.path)
        try save()
        return Change(name: destination.lastPathComponent, path: destination.path, conflict: conflict)
    }

    private func localComponents(_ file: RemoteFile, courseID: String, root: URL) throws -> [String] {
        guard !file.components.isEmpty, file.components.count == file.componentIDs.count,
              file.componentIDs.last == file.id,
              file.components.count == 1 || file.componentIDs.first == courseID else { throw StudSyncError.unsafePath }
        try SafePath.validateRemoteID(courseID)
        var result: [String] = []
        for (index, id) in file.componentIDs.enumerated() {
            try SafePath.validateRemoteID(id)
            let isFile = index == file.components.count - 1
            let kind = isFile ? "file" : (index == 0 ? "course" : "folder")
            let name = try SafePath.suffixedComponent(file.components[index], suffix: "", isFile: isFile)
            let parent = result.isEmpty ? root.standardizedFileURL.resolvingSymlinksInPath()
                : try SafePath.destination(root: root, components: result)
            let parentKey = Self.folded(parent.path)
            let identity = kind + "-" + id + "/" + name
            var assigned = names[parentKey] ?? [:]
            if let saved = assigned[identity] { result.append(saved); continue }
            let reserved = Set(assigned.values.map(Self.folded))
            var candidate = name
            var number = 1
            while true {
                let target = try SafePath.destination(root: root, components: result + [candidate])
                var directory: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: target.path, isDirectory: &directory)
                if !reserved.contains(Self.folded(candidate)), !reservedPaths.contains(Self.folded(target.path)),
                   !(exists && directory.boolValue == isFile) { break }
                number += 1
                candidate = try SafePath.suffixedComponent(name, suffix: " (\(number))", isFile: isFile)
            }
            assigned[identity] = candidate
            names[parentKey] = assigned
            result.append(candidate)
        }
        return result
    }

    private static func folded(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func migrateIDNamedFile(key: String, fileID: String, target: URL, root: URL, components: [String]) throws {
        guard var record = records[key], record.baselineHash != nil, let path = record.targetPath,
              path != target.path, !FileManager.default.fileExists(atPath: target.path) else { return }
        let source = URL(fileURLWithPath: path).standardizedFileURL
        let marker = " [file-\(fileID)]"
        guard source.deletingPathExtension().lastPathComponent.hasSuffix(marker) || source.lastPathComponent.hasSuffix(marker),
              FileManager.default.fileExists(atPath: source.path) else { return }
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        guard source.path.hasPrefix(root.path + "/") else { throw StudSyncError.unsafePath }
        let oldComponents = source.path.dropFirst(root.path.count + 1).split(separator: "/").map(String.init)
        _ = try SafePath.destination(root: root, components: oldComponents)
        guard try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try SafePath.destination(root: root, components: components)
        _ = try SafePath.destination(root: root, components: oldComponents)
        try FileManager.default.moveItem(at: source, to: target)
        record.targetPath = target.path
        records[key] = record
        reservedPaths.insert(Self.folded(target.path))
        try save()
        // rmdir removes only empty directories, even if another file appears during cleanup.
        var directory = source.deletingLastPathComponent()
        while directory.path.hasPrefix(root.path + "/"), rmdir(directory.path) == 0 {
            directory.deleteLastPathComponent()
        }
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Manifest(records: records, names: names, reservedPaths: reservedPaths)).write(to: manifest, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifest.path)
    }
}
