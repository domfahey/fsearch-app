import Darwin
import Foundation

/// A read-only sanity check of the daemon's data folder (`O_NOFOLLOW` + `fstat`/`fstatat`; nothing is changed).
///
/// The folder holds the socket, `socket.lock` and the index, so a symlink, another user's
/// ownership or group/world write access there lets someone else redirect or tamper with them.
/// The daemon creates the folder with `create_dir_all` under the user's umask (normally 0755),
/// so group/other read access is normal and not reported.
public enum DataFolderCheck {
    /// One problem found.
    public enum Issue: Equatable, Sendable {
        /// The folder itself is a symbolic link.
        case folderIsSymlink
        /// The path exists but is not a directory.
        case folderNotDirectory
        /// Another user owns the folder.
        case folderNotOwned
        /// Group or others can write to the folder.
        case folderWritableByOthers
        /// `socket.lock` or `fsearch.sock` (the name) is a symbolic link.
        case fileIsSymlink(String)
        /// Another user owns `socket.lock` or `fsearch.sock` (the name).
        case fileNotOwned(String)

        /// Whether trashing the folder could follow a link or take another user's files.
        public var unsafeToTrash: Bool {
            switch self {
            case .folderIsSymlink, .folderNotOwned: true
            default: false
            }
        }

        /// A short sentence for Index Details.
        public var message: String {
            switch self {
            case .folderIsSymlink: String(localized: "The data folder is a symbolic link.", bundle: .module)
            case .folderNotDirectory: String(localized: "The data folder is not a folder.", bundle: .module)
            case .folderNotOwned: String(localized: "The data folder belongs to another user.", bundle: .module)
            case .folderWritableByOthers:
                String(localized: "The data folder can be written to by other users.", bundle: .module)
            case let .fileIsSymlink(name): String(localized: "\(name) is a symbolic link.", bundle: .module)
            case let .fileNotOwned(name): String(localized: "\(name) belongs to another user.", bundle: .module)
            }
        }
    }

    /// Files in the folder the daemon trusts.
    static let watchedFiles = ["socket.lock", "fsearch.sock"]

    /// Problems with `dir` and its socket files; empty when it is fine or doesn't exist yet.
    ///
    /// - Parameters:
    ///   - dir: The data folder (a temp folder in tests).
    ///   - uid: The user who should own everything; ours by default.
    public static func issues(in dir: URL, uid: uid_t = getuid()) -> [Issue] {
        let dirfd = open(dir.path, O_SEARCH | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        var st = stat()
        if dirfd < 0 {
            guard lstat(dir.path, &st) == 0 else { return [] }
            if st.st_mode & S_IFMT == S_IFLNK { return [.folderIsSymlink] }
            if st.st_mode & S_IFMT != S_IFDIR { return [.folderNotDirectory] }
            var found: [Issue] = []
            if st.st_uid != uid { found.append(.folderNotOwned) }
            if st.st_mode & (S_IWGRP | S_IWOTH) != 0 { found.append(.folderWritableByOthers) }
            return found
        }
        defer { close(dirfd) }
        guard fstat(dirfd, &st) == 0 else { return [] }
        var found: [Issue] = []
        if st.st_uid != uid { found.append(.folderNotOwned) }
        if st.st_mode & (S_IWGRP | S_IWOTH) != 0 { found.append(.folderWritableByOthers) }
        for name in watchedFiles {
            var f = stat()
            guard fstatat(dirfd, name, &f, AT_SYMLINK_NOFOLLOW) == 0 else { continue }
            if f.st_mode & S_IFMT == S_IFLNK {
                found.append(.fileIsSymlink(name))
            } else if f.st_uid != uid {
                found.append(.fileNotOwned(name))
            }
        }
        return found
    }
}
