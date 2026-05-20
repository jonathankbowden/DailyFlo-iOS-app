import Foundation
import Supabase

extension SupabaseClient {
    static let shared: SupabaseClient = {
        let url = SupabaseConfiguration.url
        let key = SupabaseConfiguration.publishableKey
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()
}

private enum SupabaseConfiguration {
    static var url: URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !raw.isEmpty,
              raw != "https://YOUR_SUPABASE_URL",
              let url = URL(string: raw)
        else {
            fatalError("SUPABASE_URL missing or unresolved. Set it in SupabaseConfig.xcconfig and confirm the xcconfig is attached to the Debug/Release configurations.")
        }
        return url
    }

    static var publishableKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String,
              !key.isEmpty,
              key != "YOUR_PUBLISHABLE_KEY"
        else {
            fatalError("SUPABASE_PUBLISHABLE_KEY missing or unresolved. Set it in SupabaseConfig.xcconfig and confirm the xcconfig is attached to the Debug/Release configurations.")
        }
        return key
    }
}
