import Foundation

/// Shared `POST /v1/auth/device` client for Debug bootstrap and Release Profile UI (D-46 / #89).
/// Never persists the enrollment secret. Does not touch Keychain until `enrollAndSave` succeeds.
enum DeviceTokenEnrollment {
    enum EnrollmentError: Error, Equatable {
        case emptySecret
        case transport
        case httpStatus(Int)
        case invalidResponse
    }

    /// Test override; production keeps `URLSession.shared`.
    static var urlSession: URLSession = .shared

    static func resetTestHooks() {
        urlSession = .shared
    }

    /// Parses `{ "deviceToken": "…" }` from an enroll response body.
    static func parseDeviceToken(from data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = (obj["deviceToken"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    /// Fetches a fresh device token. Does **not** write Keychain.
    static func fetchDeviceToken(
        baseURL: URL,
        enrollmentSecret: String,
        session: URLSession? = nil
    ) async throws -> String {
        let secret = enrollmentSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { throw EnrollmentError.emptySecret }

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/auth/device"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await (session ?? urlSession).data(for: request)
        } catch {
            throw EnrollmentError.transport
        }

        guard let http = response as? HTTPURLResponse else {
            throw EnrollmentError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw EnrollmentError.httpStatus(http.statusCode)
        }
        guard let token = parseDeviceToken(from: data) else {
            throw EnrollmentError.invalidResponse
        }
        return token
    }

    /// Enrolls via the Worker and saves the issued token to Keychain.
    /// On any failure the Keychain is left unchanged.
    @discardableResult
    static func enrollAndSave(
        baseURL: URL,
        enrollmentSecret: String,
        session: URLSession? = nil
    ) async -> Bool {
        do {
            let token = try await fetchDeviceToken(
                baseURL: baseURL,
                enrollmentSecret: enrollmentSecret,
                session: session
            )
            return DeviceTokenStore.save(token)
        } catch {
            return false
        }
    }
}
