import Foundation

/// Resolves the outfit-engine base URL (never localhost on a physical device).
/// Priority (DEBUG builds): launch arg `-outfitEngineBaseURL` → env `OUTFIT_ENGINE_BASE_URL`
/// → Info.plist `OUTFIT_ENGINE_BASE_URL` → simulator-only local bridge → device public HTTPS.
/// In Release/TestFlight builds the launch-arg and env overrides are compiled out (#180), so the
/// base URL cannot be repointed to an arbitrary host: only Info.plist / the public HTTPS default apply.
enum EngineConfig {
    static let defaultLocalBase = "http://127.0.0.1:8787"
    /// Placeholder host. Supply the real one via Info.plist (`OUTFIT_ENGINE_BASE_URL` from the untracked LocalSecrets.xcconfig).
    static let defaultPublicHTTPSBase = "https://stylist-backend.example.invalid"

    /// Whether launch-arg / env overrides are compiled into this build (#180).
    /// `true` in DEBUG (Simulator demo); `false` in Release/TestFlight.
    #if DEBUG
    static let allowsLaunchArgAndEnvOverride = true
    #else
    static let allowsLaunchArgAndEnvOverride = false
    #endif

    static var baseURL: URL {
        if let raw = resolvedBaseString(), let url = URL(string: raw), url.scheme != nil {
            return url
        }
        #if targetEnvironment(simulator)
        return URL(string: defaultLocalBase)!
        #else
        return URL(string: defaultPublicHTTPSBase)!
        #endif
    }

    static var isRemoteHTTPS: Bool {
        baseURL.scheme?.lowercased() == "https"
    }

    private static func resolvedBaseString() -> String? {
        #if DEBUG
        // Launch-arg and env overrides are debug-only affordances for the
        // Simulator demo (#180). In Release/TestFlight builds they are compiled
        // out so the engine base URL cannot be repointed to an arbitrary host;
        // only the baked Info.plist value (or the compiled default) is used.
        if let override = launchArgOrEnvOverride(
            arguments: ProcessInfo.processInfo.arguments,
            environment: ProcessInfo.processInfo.environment
        ) {
            return override
        }
        #endif
        if let plist = Bundle.main.object(forInfoDictionaryKey: "OUTFIT_ENGINE_BASE_URL") as? String {
            let v = plist.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { return v }
        }
        return nil
    }

    /// Pure resolution of the debug-only launch-arg / env overrides (#180).
    /// Exposed for unit tests; Release builds never call this from `resolvedBaseString`.
    static func launchArgOrEnvOverride(
        arguments: [String],
        environment: [String: String]
    ) -> String? {
        if let idx = arguments.firstIndex(of: "-outfitEngineBaseURL"),
           arguments.index(after: idx) < arguments.count {
            let v = arguments[arguments.index(after: idx)]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { return v }
        }
        if let env = environment["OUTFIT_ENGINE_BASE_URL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        return nil
    }
}
