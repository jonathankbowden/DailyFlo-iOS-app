//
//  JournalPhotoStore.swift
//  DailyFlo
//
//  On-disk storage for user-attached journal entry photos. The photo
//  lives at Documents/JournalImages/{entry.id}.jpg; `JournalEntry`
//  stores only the bare filename in `userPhotoURL` because the absolute
//  sandbox path is not stable across app installs (or even some restore
//  flows), while the Documents-relative filename always is. Resolving
//  the absolute URL happens at load time.
//

import UIKit

enum JournalPhotoStore {
    private static let folderName = "JournalImages"
    private static let jpegQuality: CGFloat = 0.85

    /// Documents/JournalImages, created lazily.
    static func directory() -> URL {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent(folderName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Persists `image` as a JPEG keyed by `entryID`. Returns the value
    /// to store in `JournalEntry.userPhotoURL` — a bare filename, not an
    /// absolute path. Returns nil if encoding or the write fails.
    @discardableResult
    static func save(_ image: UIImage, for entryID: UUID) -> String? {
        guard let data = image.jpegData(compressionQuality: jpegQuality) else { return nil }
        let name = filename(for: entryID)
        let url = directory().appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            print("[JournalPhotoStore] save failed for \(entryID): \(error)")
            return nil
        }
    }

    /// Removes the JPEG for `entryID`. No-op if no file exists.
    static func delete(for entryID: UUID) {
        let url = directory().appendingPathComponent(filename(for: entryID))
        try? FileManager.default.removeItem(at: url)
    }

    /// Loads the UIImage backing `userPhotoURL`. Tolerates three legacy
    /// shapes so any older entries still resolve:
    ///   - bare filename (the canonical format)
    ///   - absolute filesystem path
    ///   - file:// URL
    /// Returns nil if the file is unreadable for any reason; callers
    /// should fall back to the emotion photo.
    static func image(forStoredPath path: String?) -> UIImage? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("file://"), let url = URL(string: path) {
            return UIImage(contentsOfFile: url.path)
        }
        if path.hasPrefix("/") {
            return UIImage(contentsOfFile: path)
        }
        let url = directory().appendingPathComponent(path)
        return UIImage(contentsOfFile: url.path)
    }

    private static func filename(for entryID: UUID) -> String {
        "\(entryID.uuidString).jpg"
    }
}
