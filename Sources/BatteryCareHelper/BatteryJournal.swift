// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint and Aster contributors

import Darwin
import Foundation

/// Root-only durable state. The lock is shared by development and production.
/// All journal access is relative to an opened, verified directory descriptor.
protocol BatteryStateStore {
    func load() throws -> BatteryCareState
    func save(_ state: BatteryCareState) throws
}

final class BatteryJournal: BatteryStateStore {
    private var directory: Int32 = -1
    private var lock: Int32 = -1
    enum Failure: Error { case unsafePath, locked, corrupt, write }

    init() throws {
        let path = "/Library/Application Support/" + BatteryCareIdentifiers.helperID
        guard mkdir(path, 0o700) == 0 || errno == EEXIST else { throw Failure.unsafePath }
        directory = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard secure(directory, kind: S_IFDIR) else { throw Failure.unsafePath }
        lock = open("/var/run/aster-battery-care.lock", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard secure(lock, kind: S_IFREG) else { throw Failure.unsafePath }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { throw Failure.locked }
    }

    deinit {
        if directory >= 0 { close(directory) }
        if lock >= 0 { close(lock) }
    }

    func load() throws -> BatteryCareState {
        let file = openat(directory, "state.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        if file < 0 && errno == ENOENT { return BatteryCareState() }
        guard secure(file, kind: S_IFREG) else { if file >= 0 { close(file) }; throw Failure.corrupt }
        defer { close(file) }
        var buffer = [UInt8](repeating: 0, count: 131073)
        let count = read(file, &buffer, buffer.count)
        guard count > 0, count <= 131072,
              let state = try? JSONDecoder().decode(BatteryCareState.self, from: Data(buffer.prefix(count))),
              state.isValid else { throw Failure.corrupt }
        return state
    }

    func save(_ state: BatteryCareState) throws {
        guard state.isValid else { throw Failure.corrupt }
        let data = try JSONEncoder().encode(state)
        guard data.count <= 131072 else { throw Failure.write }
        let name = "state-" + UUID().uuidString + ".tmp"
        let file = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard secure(file, kind: S_IFREG) else { throw Failure.write }
        defer { close(file); unlinkat(directory, name, 0) }
        let count = data.withUnsafeBytes { write(file, $0.baseAddress, $0.count) }
        guard count == data.count, fsync(file) == 0,
              renameat(directory, name, directory, "state.json") == 0,
              fsync(directory) == 0 else { throw Failure.write }
    }

    private func secure(_ descriptor: Int32, kind: mode_t) -> Bool {
        var info = stat()
        guard descriptor >= 0, fstat(descriptor, &info) == 0 else { return false }
        return info.st_uid == 0 && info.st_mode & S_IFMT == kind
            && info.st_mode & 0o077 == 0 && (kind == S_IFDIR || info.st_nlink == 1)
    }
}
