// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// All content reads use local descriptors, refuse symlinks and suppress
/// dataless-file materialization for the duration of this worker thread.
enum StorageLocalAccess {
    static let excludedComponents: Set<String> = [
        "library", ".trash", ".trashes", ".spotlight-v100", ".fseventsd", ".timemachine",
        ".ssh", ".gnupg", ".aws", ".azure", ".config", ".kube", ".git", "keychains",
        "cloudstorage", "mobile documents", "shared", "group containers", "containers"
    ]
    static let excludedExtensions: Set<String> = [
        "app", "bundle", "framework", "photoslibrary", "photolibrary", "musiclibrary",
        "sparsebundle", "backupbundle", "keychain", "keychain-db", "p12", "pfx", "pem", "key"
    ]

    static func pathEligible(_ url: URL) -> Bool {
        let parts = url.pathComponents.map { $0.lowercased() }
        guard !parts.contains(where: { excludedComponents.contains($0) }),
              !parts.contains(where: { excludedExtensions.contains(($0 as NSString).pathExtension) }) else { return false }
        let deniedRoots = ["/System", "/Library", "/usr", "/bin", "/sbin", "/opt", "/dev", "/cores",
                           "/private/etc", "/private/var/db", "/private/var/root"]
        guard !deniedRoots.contains(where: { url.path == $0 || url.path.hasPrefix($0 + "/") }) else { return false }
        if url.path.hasPrefix("/Users/"), !StorageInspectionPolicy.isWithin(url, root: URL(fileURLWithPath: NSHomeDirectory())) { return false }
        return !parts.contains { part in
            ["dropbox", "onedrive", "googledrive", "google drive", "box sync", "icloud drive"].contains { part.hasPrefix($0) }
        }
    }

    static func canonicalRoot(_ url: URL) throws -> URL {
        var path = url
        while path.path != "/" {
            if UninstallerSupport.isSymbolicLink(path), !["/var", "/tmp", "/etc"].contains(path.path) {
                throw StorageInspectionFailure.excluded
            }
            path.deleteLastPathComponent()
        }
        guard let resolved = realpath(url.path, nil) else { throw StorageInspectionFailure.unavailable }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    static func withoutMaterializing<T>(_ operation: () throws -> T) rethrows -> T {
        let old = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        let changed = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
                                    IOPOL_MATERIALIZE_DATALESS_FILES_OFF) == 0
        defer { if changed, old >= 0 { _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, old) } }
        return try operation()
    }

    static func metadata(_ url: URL) throws -> stat {
        guard pathEligible(url) else { throw StorageInspectionFailure.excluded }
        var value = stat()
        guard lstat(url.path, &value) == 0 else { throw errno == EACCES ? StorageInspectionFailure.denied : .unavailable }
        guard (value.st_mode & S_IFMT) != S_IFLNK, value.st_flags & UInt32(SF_DATALESS) == 0,
              value.st_uid == geteuid(), value.st_mode & 0o022 == 0, !hasSharedGrant(url),
              pathEligible(url) else { throw StorageInspectionFailure.excluded }
        let resource = try url.resourceValues(forKeys: [.isUbiquitousItemKey, .isAliasFileKey, .isPackageKey, .volumeIsLocalKey])
        guard resource.isUbiquitousItem != true, resource.isAliasFile != true,
              resource.isPackage != true, resource.volumeIsLocal == true else { throw StorageInspectionFailure.excluded }
        return value
    }

    static func identity(_ value: stat) -> UninstallerSupport.FileIdentity {
        .init(device: UInt64(value.st_dev), inode: UInt64(value.st_ino))
    }

    static func ancestors(of url: URL) throws -> [StorageAncestor] {
        var path = url.deletingLastPathComponent()
        var values: [StorageAncestor] = []
        while path.path != "/" {
            var value = stat()
            guard lstat(path.path, &value) == 0, (value.st_mode & S_IFMT) == S_IFDIR else { throw StorageInspectionFailure.changed }
            values.append(.init(url: path, identity: identity(value)))
            path.deleteLastPathComponent()
        }
        return values
    }

    static func validateAncestors(_ ancestors: [StorageAncestor]) throws {
        for ancestor in ancestors {
            var value = stat()
            guard lstat(ancestor.url.path, &value) == 0, (value.st_mode & S_IFMT) == S_IFDIR,
                  identity(value) == ancestor.identity, value.st_flags & UInt32(SF_DATALESS) == 0 else {
                throw StorageInspectionFailure.changed
            }
        }
    }

    static func snapshot(_ url: URL, root: URL, value: stat) throws -> StorageFileSnapshot {
        guard (value.st_mode & S_IFMT) == S_IFREG else { throw StorageInspectionFailure.excluded }
        return .init(url: url, root: root, identity: identity(value), logicalBytes: value.st_size,
                     allocatedBytes: Int64(value.st_blocks) * 512, modifiedSeconds: Int64(value.st_mtimespec.tv_sec),
                     modifiedNanoseconds: Int64(value.st_mtimespec.tv_nsec), ancestors: try ancestors(of: url))
    }

    static func matches(_ value: stat, _ file: StorageFileSnapshot) -> Bool {
        (value.st_mode & S_IFMT) == S_IFREG && identity(value) == file.identity
            && value.st_size == file.logicalBytes && Int64(value.st_mtimespec.tv_sec) == file.modifiedSeconds
            && Int64(value.st_mtimespec.tv_nsec) == file.modifiedNanoseconds && value.st_flags & UInt32(SF_DATALESS) == 0
    }

    static func validate(_ file: StorageFileSnapshot) throws {
        guard StorageInspectionPolicy.isWithin(file.url, root: file.root) else { throw StorageInspectionFailure.changed }
        try validateAncestors(file.ancestors)
        for ancestor in file.ancestors where StorageInspectionPolicy.isWithin(ancestor.url, root: file.root) {
            _ = try metadata(ancestor.url)
        }
        guard matches(try metadata(file.url), file) else { throw StorageInspectionFailure.changed }
    }

    static func openVerified(_ file: StorageFileSnapshot) throws -> FileHandle {
        try validate(file)
        let fd = try openWithoutLinks(file.url)
        var value = stat()
        guard fstat(fd, &value) == 0, matches(value, file) else { close(fd); throw StorageInspectionFailure.changed }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    private static func openWithoutLinks(_ url: URL) throws -> Int32 {
        var parent = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parent >= 0 else { throw StorageInspectionFailure.denied }
        let parts = Array(url.pathComponents.dropFirst())
        for (index, part) in parts.enumerated() {
            let flags = O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC | (index < parts.count - 1 ? O_DIRECTORY : 0)
            let next = openat(parent, part, flags)
            close(parent)
            guard next >= 0 else { throw StorageInspectionFailure.changed }
            parent = next
        }
        return parent
    }

    private static func hasSharedGrant(_ url: URL) -> Bool {
        guard let acl = acl_get_file(url.path, ACL_TYPE_EXTENDED) else { return false }
        defer { acl_free(UnsafeMutableRawPointer(acl)) }
        var entry: acl_entry_t?
        var entryID = ACL_FIRST_ENTRY.rawValue
        while acl_get_entry(acl, entryID, &entry) == 0 {
            entryID = ACL_NEXT_ENTRY.rawValue
            guard let entry else { break }
            var tag = ACL_UNDEFINED_TAG
            if acl_get_tag_type(entry, &tag) == 0, tag == ACL_EXTENDED_ALLOW { return true }
        }
        return false
    }

    static func validateEnd(_ handle: FileHandle, file: StorageFileSnapshot) throws {
        var value = stat()
        guard fstat(handle.fileDescriptor, &value) == 0, matches(value, file) else { throw StorageInspectionFailure.changed }
        try validate(file)
    }
}
