//
//  MeditationCatalog.swift
//  DailyFlo
//
//  Source of truth for the Pause catalog. Fetches active rows from the
//  Supabase `meditations` table (one row per theme × duration), groups them
//  into the themed `MeditationSession`s the Pause UI renders, caches the last
//  good result to disk, and falls back to the bundled list when the fetch
//  fails and nothing is cached. The bundled list lives here, and ONLY here,
//  as that fallback — there is no second hardcoded catalog anywhere else.
//

import Foundation
import Supabase

@MainActor
@Observable
final class MeditationCatalog {
    static let shared = MeditationCatalog()

    private init() {}

    // MARK: - Row model (maps the columns the app reads from `meditations`)

    /// One (theme, duration) slot. `Codable` so the same shape is reused for
    /// the Supabase decode and the on-disk cache.
    private struct CatalogRow: Codable {
        let themeKey: String
        let title: String
        let phase: String
        let durationMinutes: Int
        let imageName: String
        let audioPath: String?      // Storage path (streaming, later)
        let bundledAudio: String?   // bundled MP3 resource name (today)
        let ambientSound: String    // synth fallback
        let sortOrder: Int

        enum CodingKeys: String, CodingKey {
            case themeKey = "theme_key"
            case title
            case phase
            case durationMinutes = "duration_minutes"
            case imageName = "image_name"
            case audioPath = "audio_path"
            case bundledAudio = "bundled_audio"
            case ambientSound = "ambient_sound"
            case sortOrder = "sort_order"
        }
    }

    // MARK: - Load

    /// Fetches the active catalog, groups it into themed sessions, and caches
    /// the raw rows on success. On any failure (offline, decode, empty), returns
    /// the last good cache, then the bundled fallback — so Pause always has a
    /// catalog to show.
    func load() async -> [MeditationSession] {
        do {
            let rows: [CatalogRow] = try await SupabaseClient.shared
                .from("meditations")
                .select("theme_key,title,phase,duration_minutes,image_name,audio_path,bundled_audio,ambient_sound,sort_order")
                .eq("is_active", value: true)
                .order("sort_order", ascending: true)
                .execute()
                .value

            guard !rows.isEmpty else { return cachedOrBundled() }
            cache(rows)
            return Self.sessions(from: rows)
        } catch {
            #if DEBUG
            print("MeditationCatalog: live fetch failed (\(error)); using cache/bundled fallback")
            #endif
            return cachedOrBundled()
        }
    }

    // MARK: - Grouping

    /// Groups rows by theme (preserving the server's `sort_order`) into one
    /// `MeditationSession` per theme. `collectibleImages` is ordered by duration
    /// [5, 10, 60] to line up with `MeditationDuration`/`imageVariant`. The
    /// streaming `audioPaths` map is filled **per slot** from every row, so no
    /// duration's `audio_path` is lost. Bundled/synth stays per theme (one loop
    /// today), taken from the shortest-duration row.
    private static func sessions(from rows: [CatalogRow]) -> [MeditationSession] {
        var order: [String] = []
        var byTheme: [String: [CatalogRow]] = [:]
        for row in rows {
            if byTheme[row.themeKey] == nil { order.append(row.themeKey) }
            byTheme[row.themeKey, default: []].append(row)
        }

        return order.compactMap { key -> MeditationSession? in
            guard let group = byTheme[key], !group.isEmpty else { return nil }
            let sorted = group.sorted { $0.durationMinutes < $1.durationMinutes }
            let images = sorted.map(\.imageName)
            let base = sorted[0]

            var audioPaths: [MeditationDuration: String] = [:]
            for row in sorted {
                guard let path = row.audioPath, !path.isEmpty,
                      let duration = MeditationDuration(rawValue: row.durationMinutes) else { continue }
                audioPaths[duration] = path
            }

            return MeditationSession(
                title: base.title,
                phase: Self.phase(from: base.phase),
                imageName: images.first ?? base.imageName,
                collectibleImages: images,
                audioFileName: base.bundledAudio,
                audioPaths: audioPaths,
                ambientSound: AmbientSoundType(rawValue: base.ambientSound) ?? .warmDrone
            )
        }
    }

    private static func phase(from raw: String) -> CyclePhase {
        switch raw {
        case "follicular": return .follicular
        case "ovulation": return .ovulation
        case "luteal": return .luteal
        default: return .menstrual   // "menstrual" and anything unexpected
        }
    }

    // MARK: - Disk cache (last good catalog, for offline)

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("meditation_catalog.json")
    }

    private func cache(_ rows: [CatalogRow]) {
        guard let data = try? JSONEncoder().encode(rows) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    /// Deletes the on-disk catalog cache. Used by account deletion to return the
    /// device to a fresh-install state.
    func clearDiskCache() {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func cachedOrBundled() -> [MeditationSession] {
        if let data = try? Data(contentsOf: cacheURL),
           let rows = try? JSONDecoder().decode([CatalogRow].self, from: data),
           !rows.isEmpty {
            return Self.sessions(from: rows)
        }
        return Self.bundledFallback
    }

    // MARK: - Bundled fallback (the ONLY hardcoded catalog)

    /// The 10 themes shipped in the app bundle, used only when the live fetch
    /// fails and there's no cache yet. Mirrors the 30 seeded rows collapsed to
    /// one session per theme; `collectibleImages` is [_a (5), _b (10), _c (60)].
    static let bundledFallback: [MeditationSession] = [
        // Menstrual
        MeditationSession(
            title: "MIST",
            phase: .menstrual,
            imageName: "medbg_mist_a",
            collectibleImages: ["medbg_mist_a", "medbg_mist_b", "medbg_mist_c"],
            audioFileName: "mist_05min",
            ambientSound: .gentleRain
        ),
        MeditationSession(
            title: "NIGHT SKY",
            phase: .menstrual,
            imageName: "medbg_nightsky_a",
            collectibleImages: ["medbg_nightsky_a", "medbg_nightsky_b", "medbg_nightsky_c"],
            audioFileName: "nightsky_05min",
            ambientSound: .nightAmbience
        ),
        MeditationSession(
            title: "STILLWATER",
            phase: .menstrual,
            imageName: "medbg_stillwater_a",
            collectibleImages: ["medbg_stillwater_a", "medbg_stillwater_b", "medbg_stillwater_c"],
            audioFileName: "stillwater_05min",
            ambientSound: .warmDrone
        ),
        // Follicular
        MeditationSession(
            title: "CANOPY",
            phase: .follicular,
            imageName: "medbg_canopy_a",
            collectibleImages: ["medbg_canopy_a", "medbg_canopy_b", "medbg_canopy_c"],
            audioFileName: "canopy_05min",
            ambientSound: .forestBreeze
        ),
        MeditationSession(
            title: "OPEN HILLS",
            phase: .follicular,
            imageName: "medbg_openhills_a",
            collectibleImages: ["medbg_openhills_a", "medbg_openhills_b", "medbg_openhills_c"],
            audioFileName: "openhills_05min",
            ambientSound: .forestBreeze
        ),
        // Ovulation
        MeditationSession(
            title: "GOLDEN HOUR",
            phase: .ovulation,
            imageName: "medbg_goldenhour_a",
            collectibleImages: ["medbg_goldenhour_a", "medbg_goldenhour_b", "medbg_goldenhour_c"],
            audioFileName: "goldenhour_05min",
            ambientSound: .softChimes
        ),
        MeditationSession(
            title: "OCEAN",
            phase: .ovulation,
            imageName: "medbg_ocean_a",
            collectibleImages: ["medbg_ocean_a", "medbg_ocean_b", "medbg_ocean_c"],
            audioFileName: "ocean_05min",
            ambientSound: .oceanWaves
        ),
        // Luteal
        MeditationSession(
            title: "STORM",
            phase: .luteal,
            imageName: "medbg_storm_a",
            collectibleImages: ["medbg_storm_a", "medbg_storm_b", "medbg_storm_c"],
            audioFileName: "storm_05min",
            ambientSound: .gentleRain
        ),
        MeditationSession(
            title: "FOREST",
            phase: .luteal,
            imageName: "medbg_forest_a",
            collectibleImages: ["medbg_forest_a", "medbg_forest_b", "medbg_forest_c"],
            audioFileName: "forest_05min",
            ambientSound: .forestBreeze
        ),
        MeditationSession(
            title: "SOLITUDE",
            phase: .luteal,
            imageName: "medbg_solitude_a",
            collectibleImages: ["medbg_solitude_a", "medbg_solitude_b", "medbg_solitude_c"],
            audioFileName: "solitude_05min",
            ambientSound: .warmDrone
        )
    ]
}
