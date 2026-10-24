import Foundation

/// Connection settings for the Supabase project.
///
/// Resolution order: `SUPABASE_URL` / `SUPABASE_ANON_KEY` environment variables (set them in the
/// scheme for local development), then `Supabase.plist` in the app bundle. When neither is filled
/// in, the app runs on local preview data exactly like the Section 1 build.
///
/// The anon (publishable) key is safe to ship in the app: every table is protected by row level
/// security, and status changes go through server-side functions.
struct SupabaseConfig {
    let url: URL
    let anonKey: String

    static func load(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) -> SupabaseConfig? {
        let plist = bundle.url(forResource: "Supabase", withExtension: "plist")
            .flatMap { NSDictionary(contentsOf: $0) as? [String: Any] } ?? [:]

        func value(_ key: String) -> String? {
            let raw = environment[key] ?? plist[key] as? String
            guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty,
                  !trimmed.hasPrefix("YOUR_"),
                  !trimmed.contains("$(") else { return nil }
            return trimmed
        }

        guard let urlString = value("SUPABASE_URL"),
              let url = URL(string: urlString),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil,
              let key = value("SUPABASE_ANON_KEY") else { return nil }
        return SupabaseConfig(url: url, anonKey: key)
    }
}
