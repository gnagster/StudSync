import Foundation
import Testing
@testable import StudSyncCore

private struct Scratch {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    init() throws { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func download(_ text: String) throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString)
        try Data(text.utf8).write(to: url)
        return url
    }
}

@Test func normalizedPathsCannotEscape() throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    for name in ["", ".", "..", "．．", "\u{0000}"] {
        #expect(throws: StudSyncError.self) { try SafePath.destination(root: scratch.root, components: [name]) }
    }
    #expect(try SafePath.component("Über / notes") == "Über -- notes")
    let outside = try Scratch(); defer { outside.remove() }
    try FileManager.default.createSymbolicLink(at: scratch.root.appendingPathComponent("escape"), withDestinationURL: outside.root)
    #expect(throws: StudSyncError.self) { try SafePath.destination(root: scratch.root, components: ["escape", "file"]) }
}

@Test func remoteNamesStayReadableAndKeepExtensions() throws {
    let names = ["①.pdf", "1.pdf", "a/b.pdf", "a--b.pdf", "NOTES.pdf", "notes.pdf"]
    let components = try names.enumerated().map {
        try SafePath.remoteComponent($0.element, id: String($0.offset, radix: 16), isFile: true)
    }
    #expect(components.allSatisfy { $0.hasSuffix(".pdf") })
    #expect(try SafePath.remoteComponent("Notes [1].pdf", id: "aa", isFile: true) == "Notes [1].pdf")
    #expect(try SafePath.remoteComponent("Course", id: "aa", isFile: false) == "Course")
    let long = try SafePath.remoteComponent(String(repeating: "ü", count: 200) + ".pdf", id: "aa", isFile: true)
    #expect(long.utf8.count <= 255)
    #expect(long.hasSuffix(".pdf"))
    #expect(throws: StudSyncError.self) { try SafePath.remoteComponent("file", id: "../bad", isFile: true) }
    #expect(throws: StudSyncError.self) { try SafePath.remoteComponent("．．", id: "aa", isFile: false) }
}

@Test func normalizedRemoteFilesNeverShareTheirBaselines() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let root = scratch.root.appendingPathComponent("sync")
    let engine = try SyncEngine(manifest: scratch.root.appendingPathComponent("manifest.json"))
    var first = RemoteFile(id: "aa", components: ["①.pdf"], componentIDs: ["aa"], size: 4, revision: "1")
    let second = RemoteFile(id: "bb", components: ["1.pdf"], componentIDs: ["bb"], size: 4, revision: "1")
    for file in [first, second] {
        _ = try await engine.synchronize(file, courseID: "cc", root: root) { try scratch.download("same") }
    }
    first.revision = "2"
    _ = try await engine.synchronize(first, courseID: "cc", root: root) { try scratch.download("next") }
    let skipped = try await engine.synchronize(second, courseID: "cc", root: root) { throw URLError(.badURL) }
    #expect(skipped == nil)
    #expect(try String(contentsOf: root.appendingPathComponent("1.pdf"), encoding: .utf8) == "next")
    #expect(try String(contentsOf: root.appendingPathComponent("1 (2).pdf"), encoding: .utf8) == "same")
}

@Test func readableAssignmentsSeparateFoldersFilesAndDuplicateCoursesAfterRestart() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let root = scratch.root.appendingPathComponent("sync")
    let manifest = scratch.root.appendingPathComponent("manifest.json")
    let engine = try SyncEngine(manifest: manifest)
    let files = [
        RemoteFile(id: "aa", components: ["Course", "Notes"], componentIDs: ["cc", "aa"], size: 4, revision: "1"),
        RemoteFile(id: "bb", components: ["Course", "Notes", "1.pdf"], componentIDs: ["cc", "dd", "bb"], size: 4, revision: "1"),
        RemoteFile(id: "ee", components: ["Course", "notes", "①.pdf"], componentIDs: ["cc", "ff", "ee"], size: 4, revision: "1"),
        RemoteFile(id: "bb", components: ["Course", "1.pdf"], componentIDs: ["99", "bb"], size: 4, revision: "1")
    ]
    var paths: [String] = []
    for file in files {
        let change = try #require(await engine.synchronize(file, courseID: file.componentIDs[0], root: root) { try scratch.download("same") })
        paths.append(change.path)
    }
    #expect(paths == ["Course/Notes", "Course/Notes (2)/1.pdf", "Course/notes (3)/1.pdf", "Course (2)/1.pdf"].map { root.appendingPathComponent($0).path })
    let restored = try SyncEngine(manifest: manifest)
    for file in files.reversed() {
        #expect(try await restored.synchronize(file, courseID: file.componentIDs[0], root: root) { throw URLError(.badURL) } == nil)
    }
    let settings = try FileManager.default.attributesOfItem(atPath: manifest.path)
    #expect(settings[.posixPermissions] as? Int == 0o600)
}

@Test func normalizedAndLongCollisionsNeverTakeOverAnotherFilesName() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let manifest = scratch.root.appendingPathComponent("manifest.json")
    let root = scratch.root.appendingPathComponent("sync")
    let engine = try SyncEngine(manifest: manifest)
    let names = ["①.pdf", "1.pdf", "NOTES.pdf", "notes.pdf", "a/b.pdf", "a--b.pdf",
                 String(repeating: "ü", count: 200) + "a.pdf", String(repeating: "ü", count: 200) + "b.pdf"]
    var paths: [String] = []
    var files: [RemoteFile] = []
    for (index, name) in names.enumerated() {
        let id = String(index, radix: 16)
        let file = RemoteFile(id: id, components: [name], componentIDs: [id], size: 4, revision: "1")
        let change = try #require(await engine.synchronize(file, courseID: "cc", root: root) { try scratch.download("same") })
        #expect(change.name.precomposedStringWithCanonicalMapping.utf8.count <= 255)
        #expect(change.name.hasSuffix(".pdf"))
        paths.append(change.path)
        files.append(file)
    }
    #expect(Set(paths.map { $0.lowercased() }).count == names.count)
    let restored = try SyncEngine(manifest: manifest)
    for file in files.reversed() {
        #expect(try await restored.synchronize(file, courseID: "cc", root: root) { throw URLError(.badURL) } == nil)
    }
    // A newly enrolled resource must not adopt an old resource's identical bytes and later overwrite it.
    let replacement = RemoteFile(id: "ff", components: ["1.pdf"], componentIDs: ["ff"], size: 4, revision: "1")
    let change = try #require(await restored.synchronize(replacement, courseID: "cc", root: root) { try scratch.download("next") })
    #expect(!paths.contains(change.path))
    for path in paths { #expect(try String(contentsOfFile: path, encoding: .utf8) == "same") }
}

@Test func legacyManifestAndEditedIdNamesSurviveTheReadableNameUpgrade() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let root = scratch.root.appendingPathComponent("sync")
    let target = root.appendingPathComponent("Course [cc]/notes [file-aa].pdf")
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("mine".utf8).write(to: target)
    let unknown = target.deletingLastPathComponent().appendingPathComponent("keep.txt")
    try Data("keep".utf8).write(to: unknown)
    let baseline = try scratch.download("same")
    let manifest = scratch.root.appendingPathComponent("manifest.json")
    let key = root.path + "/cc/aa"
    try JSONSerialization.data(withJSONObject: [key: ["revision": "1", "targetPath": target.path,
                                                    "baselineHash": SyncEngine.hash(baseline)]]).write(to: manifest)
    let engine = try SyncEngine(manifest: manifest)
    let file = RemoteFile(id: "aa", components: ["Course", "notes.pdf"], componentIDs: ["cc", "aa"], size: 4, revision: "2")
    let change = try #require(await engine.synchronize(file, courseID: "cc", root: root) { try scratch.download("next") })
    #expect(change.conflict)
    #expect(change.path.hasPrefix(root.appendingPathComponent("Course").path + "/notes (StudIP "))
    #expect(try String(contentsOf: root.appendingPathComponent("Course/notes.pdf"), encoding: .utf8) == "mine")
    #expect(!FileManager.default.fileExists(atPath: target.path))
    #expect(try String(contentsOf: unknown, encoding: .utf8) == "keep")
    let restored = try SyncEngine(manifest: manifest)
    let impersonator = RemoteFile(id: "bb", components: ["Course [cc]", "notes [file-aa].pdf"], componentIDs: ["dd", "bb"], size: 4, revision: "1")
    let other = try #require(await restored.synchronize(impersonator, courseID: "dd", root: root) { try scratch.download("mine") })
    #expect(other.path != target.path)
    #expect(!FileManager.default.fileExists(atPath: target.path))
    #expect(try String(contentsOf: unknown, encoding: .utf8) == "keep")
    #expect(try await restored.synchronize(file, courseID: "cc", root: root) { throw URLError(.badURL) } == nil)
}

@Test func invalidIdentityChainsAndSymlinksAreRejectedBeforeFetching() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let engine = try SyncEngine(manifest: scratch.root.appendingPathComponent("manifest.json"))
    for ids in [["cc"], ["dd", "aa"], ["cc", "../aa"], ["cc", "bb"]] {
        let file = RemoteFile(id: "aa", components: ["Course", "notes.pdf"], componentIDs: ids, size: 4, revision: "1")
        await #expect(throws: StudSyncError.self) {
            try await engine.synchronize(file, courseID: "cc", root: scratch.root) { Issue.record("Invalid identities must not download"); throw URLError(.badURL) }
        }
    }
    let outside = try Scratch(); defer { outside.remove() }
    try FileManager.default.createSymbolicLink(at: scratch.root.appendingPathComponent("Course"), withDestinationURL: outside.root)
    let file = RemoteFile(id: "aa", components: ["Course", "notes.pdf"], componentIDs: ["cc", "aa"], size: 4, revision: "1")
    await #expect(throws: StudSyncError.self) {
        try await engine.synchronize(file, courseID: "cc", root: scratch.root) { Issue.record("Symlinks must not download"); throw URLError(.badURL) }
    }
}

@Test func unchangedLegacyFilesMoveWithoutDownloadingAndOnlyEmptyFoldersAreRemoved() async throws {
    for contents in ["same", "edit"] {
        let scratch = try Scratch(); defer { scratch.remove() }
        let root = scratch.root.appendingPathComponent("sync")
        let old = root.appendingPathComponent("Course [cc]/Notes [folder-dd]/notes [file-aa].pdf")
        try FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: old)
        let baseline = try scratch.download("same")
        let manifest = scratch.root.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: [root.path + "/cc/aa": ["revision": "1", "targetPath": old.path,
                                                                          "baselineHash": SyncEngine.hash(baseline)]]).write(to: manifest)
        let engine = try SyncEngine(manifest: manifest)
        let file = RemoteFile(id: "aa", components: ["Course", "Notes", "notes.pdf"], componentIDs: ["cc", "dd", "aa"], size: 4, revision: "1")
        #expect(try await engine.synchronize(file, courseID: "cc", root: root) { throw URLError(.badURL) } == nil)
        let target = root.appendingPathComponent("Course/Notes/notes.pdf")
        #expect(try String(contentsOf: target, encoding: .utf8) == contents)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Course [cc]").path))
        #expect(FileManager.default.fileExists(atPath: root.path))
    }
}

@Test func legacyMigrationRejectsSymlinksAndPathsOutsideTheSyncRoot() async throws {
    for useSymlink in [false, true] {
        let scratch = try Scratch(); defer { scratch.remove() }
        let outside = try Scratch(); defer { outside.remove() }
        let outsideFile = outside.root.appendingPathComponent("notes [file-aa].pdf")
        try Data("user".utf8).write(to: outsideFile)
        var source = outsideFile
        if useSymlink {
            source = scratch.root.appendingPathComponent(outsideFile.lastPathComponent)
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: outsideFile)
        }
        let manifest = scratch.root.appendingPathComponent("manifest.json")
        try JSONSerialization.data(withJSONObject: [scratch.root.path + "/cc/aa": ["revision": "1", "targetPath": source.path,
                                                                                  "baselineHash": SyncEngine.hash(outsideFile)]]).write(to: manifest)
        let engine = try SyncEngine(manifest: manifest)
        let file = RemoteFile(id: "aa", components: ["Course", "notes.pdf"], componentIDs: ["cc", "aa"], size: 4, revision: "2")
        await #expect(throws: StudSyncError.self) {
            try await engine.synchronize(file, courseID: "cc", root: scratch.root) { Issue.record("Unsafe migration must not fetch"); throw URLError(.badURL) }
        }
        #expect(try String(contentsOf: outsideFile, encoding: .utf8) == "user")
    }
}

@Test func renamedDestinationCannotReuseAnotherPathsBaselineOrSkipIt() async throws {
    for (revision, existing, incoming) in [("1", "user", "same"), ("2", "same", "next")] {
        let scratch = try Scratch(); defer { scratch.remove() }
        let engine = try SyncEngine(manifest: scratch.root.appendingPathComponent("manifest.json"))
        var remote = RemoteFile(id: "aa", components: ["old.pdf"], componentIDs: ["aa"], size: 4, revision: "1")
        _ = try await engine.synchronize(remote, courseID: "bb", root: scratch.root) { try scratch.download("same") }
        let target = scratch.root.appendingPathComponent("new.pdf")
        try Data(existing.utf8).write(to: target)
        remote.components = ["new.pdf"]; remote.revision = revision
        let change = try await engine.synchronize(remote, courseID: "bb", root: scratch.root) { try scratch.download(incoming) }
        #expect(change?.conflict == true)
        #expect(try String(contentsOf: target, encoding: .utf8) == existing)
        #expect(try String(contentsOf: scratch.root.appendingPathComponent("old.pdf"), encoding: .utf8) == "same")
        #expect(try String(contentsOf: URL(fileURLWithPath: #require(change).path), encoding: .utf8) == incoming)
    }
}

@Test func prototypeManifestDoesNotAuthorizeReplacingAnUnknownDestination() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let target = scratch.root.appendingPathComponent("notes.pdf")
    try Data("same".utf8).write(to: target)
    let manifest = scratch.root.appendingPathComponent("manifest.json")
    let key = scratch.root.standardizedFileURL.resolvingSymlinksInPath().path + "/bb/aa"
    let data = try JSONSerialization.data(withJSONObject: [key: ["revision": "1", "baselineHash": SyncEngine.hash(target)]])
    try data.write(to: manifest)
    let engine = try SyncEngine(manifest: manifest)
    let remote = RemoteFile(id: "aa", components: ["notes.pdf"], componentIDs: ["aa"], size: 4, revision: "2")
    let change = try await engine.synchronize(remote, courseID: "bb", root: scratch.root) { try scratch.download("next") }
    #expect(change?.conflict == true)
    #expect(try String(contentsOf: target, encoding: .utf8) == "same")
}

@Test func longNamesLeaveRoomForIncomingConflictCopies() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let root = scratch.root.appendingPathComponent("sync")
    let name = try SafePath.remoteComponent(String(repeating: "a", count: 300) + ".pdf", id: String(repeating: "a", count: 32), isFile: true)
    #expect(name.utf8.count == 255)
    let engine = try SyncEngine(manifest: scratch.root.appendingPathComponent("manifest.json"))
    var file = RemoteFile(id: "aa", components: [name], componentIDs: ["aa"], size: 4, revision: "1")
    _ = try await engine.synchronize(file, courseID: "bb", root: root) { try scratch.download("same") }
    let target = root.appendingPathComponent(name)
    try Data("user".utf8).write(to: target)
    file.revision = "2"
    let change = try #require(await engine.synchronize(file, courseID: "bb", root: root) { try scratch.download("next") })
    #expect(change.conflict)
    #expect(change.name.utf8.count <= 255)
    #expect(change.name.hasSuffix(".pdf"))
    #expect(try String(contentsOf: target, encoding: .utf8) == "user")
    #expect(try String(contentsOf: URL(fileURLWithPath: change.path), encoding: .utf8) == "next")
}

@Test func untouchedFilesReplaceWithoutBackupsAndSkipUnchanged() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let root = scratch.root.appendingPathComponent("sync")
    let engine = try SyncEngine(manifest: scratch.root.appendingPathComponent("manifest.json"))
    var remote = RemoteFile(id: "aa", components: ["Course", "lecture.txt"], componentIDs: ["bb", "aa"], size: 4, revision: "1")
    let first = try await engine.synchronize(remote, courseID: "bb", root: root) { try scratch.download("old!") }
    #expect(first?.conflict == false)
    remote.revision = "2"
    _ = try await engine.synchronize(remote, courseID: "bb", root: root) { try scratch.download("new!") }
    #expect(try String(contentsOf: root.appendingPathComponent("Course/lecture.txt"), encoding: .utf8) == "new!")
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Course").path) == ["lecture.txt"])
    let restored = try SyncEngine(manifest: scratch.root.appendingPathComponent("manifest.json"))
    let skipped = try await restored.synchronize(remote, courseID: "bb", root: root) { throw URLError(.badURL) }
    #expect(skipped == nil)
}

@Test func editedFilesAndUnknownExistingFilesArePreserved() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let root = scratch.root.appendingPathComponent("sync")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let target = root.appendingPathComponent("notes.txt")
    try Data("mine".utf8).write(to: target)
    let engine = try SyncEngine(manifest: scratch.root.appendingPathComponent("manifest.json"))
    let remote = RemoteFile(id: "aa", components: ["notes.txt"], componentIDs: ["aa"], size: 6, revision: "1")
    let change = try await engine.synchronize(remote, courseID: "bb", root: root) { try scratch.download("remote") }
    #expect(change?.conflict == true)
    #expect(try String(contentsOf: target, encoding: .utf8) == "mine")
    #expect(try String(contentsOf: URL(fileURLWithPath: #require(change).path), encoding: .utf8) == "remote")
    let skipped = try await engine.synchronize(remote, courseID: "bb", root: root) { throw URLError(.badURL) }
    #expect(skipped == nil)
}

@Test func identicalExistingFileIsAdoptedAndLaterEditsSurvive() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let target = scratch.root.appendingPathComponent("notes.txt")
    try Data("same".utf8).write(to: target)
    let engine = try SyncEngine(manifest: scratch.root.appendingPathComponent("manifest.json"))
    var file = RemoteFile(id: "aa", components: ["notes.txt"], componentIDs: ["aa"], size: 4, revision: "1")
    let adopted = try await engine.synchronize(file, courseID: "bb", root: scratch.root) { try scratch.download("same") }
    #expect(adopted == nil)
    try Data("user edit".utf8).write(to: target)
    file.revision = "2"
    let changed = try await engine.synchronize(file, courseID: "bb", root: scratch.root) { try scratch.download("next") }
    #expect(changed?.conflict == true)
    #expect(try String(contentsOf: target, encoding: .utf8) == "user edit")
}

@Test func incompleteAndCancelledDownloadsDoNotChangeExistingFiles() async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let target = scratch.root.appendingPathComponent("notes.txt")
    try Data("mine".utf8).write(to: target)
    let engine = try SyncEngine(manifest: scratch.root.appendingPathComponent("manifest.json"))
    let file = RemoteFile(id: "aa", components: ["notes.txt"], componentIDs: ["aa"], size: 99, revision: "1")
    await #expect(throws: StudSyncError.self) {
        try await engine.synchronize(file, courseID: "bb", root: scratch.root) { try scratch.download("short") }
    }
    await #expect(throws: CancellationError.self) {
        try await engine.synchronize(file, courseID: "bb", root: scratch.root) { throw CancellationError() }
    }
    #expect(try String(contentsOf: target, encoding: .utf8) == "mine")
    #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.root.path) == ["notes.txt"])
}

@Test(arguments: ["network", "truncated", "cancelled"], [false, true])
func failedUpdatePreservesCheckpointAndCanRetryAfterRestart(_ failure: String, _ locallyEdited: Bool) async throws {
    let scratch = try Scratch(); defer { scratch.remove() }
    let manifest = scratch.root.appendingPathComponent("manifest.json")
    let target = scratch.root.appendingPathComponent("notes.txt")
    let engine = try SyncEngine(manifest: manifest)
    let original = RemoteFile(id: "aa", components: ["notes.txt"], componentIDs: ["aa"], size: 4, revision: "1")
    _ = try await engine.synchronize(original, courseID: "bb", root: scratch.root) { try scratch.download("same") }
    if locallyEdited { try Data("mine".utf8).write(to: target) }
    let checkpoint = try Data(contentsOf: manifest)
    let update = RemoteFile(id: "aa", components: ["notes.txt"], componentIDs: ["aa"], size: 4, revision: "2")
    let transfer = Task {
        try await engine.synchronize(update, courseID: "bb", root: scratch.root) {
            if failure == "network" { throw URLError(.networkConnectionLost) }
            let file = try scratch.download(failure == "truncated" ? "ne" : "next")
            if failure == "cancelled" { withUnsafeCurrentTask { $0?.cancel() } }
            return file
        }
    }
    do {
        _ = try await transfer.value
        Issue.record("An interrupted update must fail without installing its contents")
    } catch {
        switch failure {
        case "network": #expect((error as? URLError)?.code == .networkConnectionLost)
        case "truncated": guard case StudSyncError.sizeMismatch = error else { Issue.record("Expected size mismatch, got \(error)"); return }
        default: #expect(error is CancellationError)
        }
    }
    #expect(try String(contentsOf: target, encoding: .utf8) == (locallyEdited ? "mine" : "same"))
    #expect(try Data(contentsOf: manifest) == checkpoint)
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: scratch.root.path)) == ["notes.txt", "manifest.json"])

    let restored = try SyncEngine(manifest: manifest)
    let change = try #require(await restored.synchronize(update, courseID: "bb", root: scratch.root) { try scratch.download("next") })
    #expect(change.conflict == locallyEdited)
    #expect(try String(contentsOfFile: change.path, encoding: .utf8) == "next")
    #expect(try String(contentsOf: target, encoding: .utf8) == (locallyEdited ? "mine" : "next"))
    let reloaded = try SyncEngine(manifest: manifest)
    let repeated = try await reloaded.synchronize(update, courseID: "bb", root: scratch.root) {
        Issue.record("A successful retry must persist the new revision")
        throw URLError(.badURL)
    }
    #expect(repeated == nil)
}

@Test func loginUsesCredentialFormAndRejectsForeignAction() throws {
    let html = """
    <form action="/settings"><input name="security_token" value="wrong"></form>
    <form action="/dispatch.php/login"><input name="loginname"><input name="password">
    <input type="hidden" name="security_token" value="correct"><input type="hidden" name="login_ticket" value="ticket"></form>
    """
    let (url, fields) = try StudIPClient.loginFields(html: html, username: "student", password: "test €&+")
    #expect(url.host == StudIPClient.origin.host)
    #expect(fields["security_token"] == "correct")
    #expect(fields["Login"] == "1")
    #expect(String(decoding: StudIPClient.formBody(fields), as: UTF8.self).contains("%26%2B"))
    #expect(throws: StudSyncError.self) {
        try StudIPClient.loginFields(html: html.replacingOccurrences(of: "/dispatch.php/login", with: "https://foreign.invalid/login"), username: "student", password: "test")
    }
}
