import Foundation

public enum RecorderError: Error, LocalizedError, Sendable {
    case invalidAddress, unsupportedRecorder, invalidResponse, rejected, invalidSensitivity
    public var errorDescription: String? {
        switch self {
        case .invalidAddress: "Enter the recorder’s private IPv4 address."
        case .unsupportedRecorder: "This recorder needs a different protocol adapter. No settings were changed."
        case .invalidResponse: "The recorder returned an unexpected response."
        case .rejected: "The recorder did not accept the request."
        case .invalidSensitivity: "This sensor level has not been mapped for this protocol."
        }
    }
}

public enum Camera: String, Codable, CaseIterable, Sendable {
    case front, rear, unknown
    public var title: String { rawValue.capitalized }
}

public struct RecorderSnapshot: Decodable, Sendable, Equatable {
    public let systemID: String
    public let firmware: String
    public let hardware: String
    public let drivingSensor: Int
    public let parkingSensor: Int
    public let radar: Int
    public var isUTR2: Bool { systemID == "1094863410" || systemID.uppercased() == "ABJ2" || systemID.uppercased().replacingOccurrences(of: "0X", with: "") == "41424A32" }
    enum CodingKeys: String, CodingKey { case systemID = "system_id", firmware = "fw_version", hardware = "hw_version", drivingSensor = "rec_gsensor_lv_driving", parkingSensor = "rec_gsensor_lv_parking", radar = "rec_radar_lv" }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func string(_ key: CodingKeys) throws -> String {
            if let value = try? c.decode(String.self, forKey: key) { return value }
            return String(try c.decode(Int.self, forKey: key))
        }
        func number(_ key: CodingKeys) throws -> Int {
            if let value = try? c.decode(Int.self, forKey: key) { return value }
            guard let value = Int(try c.decode(String.self, forKey: key)) else { throw RecorderError.invalidResponse }
            return value
        }
        systemID = try string(.systemID); firmware = try string(.firmware); hardware = try string(.hardware)
        drivingSensor = try number(.drivingSensor); parkingSensor = try number(.parkingSensor); radar = try number(.radar)
    }
}

/// Recovered from Audi Android V2.02. Compatibility with the owner's firmware is untested.
public struct UTR2Requests: Sendable {
    public let address: String
    public init(address: String) throws {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard parts.count == 4, numbers.count == 4, numbers.allSatisfy({ (0...255).contains($0) }),
              zip(parts, numbers).allSatisfy({ String($0.0) == String($0.1) }),
              numbers[3] > 0, numbers[3] < 255,
              numbers[0] == 10 || (numbers[0] == 192 && numbers[1] == 168) || (numbers[0] == 172 && (16...31).contains(numbers[1])) else { throw RecorderError.invalidAddress }
        self.address = address
    }
    private func post(_ endpoint: String, params: String) -> URLRequest {
        var r = URLRequest(url: URL(string: "http://\(address)/\(endpoint)")!)
        r.httpMethod = "POST"; r.setValue(params, forHTTPHeaderField: "Params")
        r.timeoutInterval = 5; r.cachePolicy = .reloadIgnoringLocalCacheData
        return r
    }
    public func settings() -> URLRequest { post("req-get.cgi", params: "?settings") }
    public func sensors(driving: Int, parking: Int, radar: Int, identity: RecorderSnapshot) throws -> URLRequest {
        guard identity.isUTR2 else { throw RecorderError.unsupportedRecorder }
        guard (0...5).contains(driving), (0...5).contains(parking), (0...3).contains(radar) else { throw RecorderError.invalidSensitivity }
        return post("req-set.cgi", params: "?rec_gsensor_lv_driving=\(driving)&rec_gsensor_lv_parking=\(parking)&rec_radar_lv=\(radar)")
    }
    public func saveSettings(identity: RecorderSnapshot) throws -> URLRequest {
        guard identity.isUTR2 else { throw RecorderError.unsupportedRecorder }
        return post("req-cmd.cgi", params: "?save_setting_param")
    }
    public static func clockValue(date: Date, zone: TimeZone) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian); f.timeZone = zone
        // Preserve the legacy literal Z followed by numeric local offset; do not substitute ISO8601DateFormatter.
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'Z"
        return f.string(from: date)
    }
    public func clock(date: Date = Date(), zone: TimeZone = .current, identity: RecorderSnapshot) throws -> URLRequest {
        guard identity.isUTR2 else { throw RecorderError.unsupportedRecorder }
        let encoded = Self.clockValue(date: date, zone: zone).addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        // userAgent token is part of the recovered V2.02 request. Firmware support remains to be tested.
        var r = URLRequest(url: URL(string: "http://\(address):8082/req-set.cgi?lang=&datetime=\(encoded)&userAgent=android")!)
        r.timeoutInterval = 5; r.cachePolicy = .reloadIgnoringLocalCacheData
        return r
    }
    public func liveURL(camera: Camera) throws -> URL {
        guard camera != .unknown else { throw RecorderError.invalidResponse }
        return URL(string: "rtsp://\(address)/H264?W=640&H=360&FPS=30&BR=1000000&V=\(camera == .front ? 0 : 1)")!
    }
}

private final class RecorderSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    // Keep camera commands on the configured endpoint; never forward them to a redirect.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public actor RecorderClient {
    private let requests: UTR2Requests
    private let session: URLSession
    public init(address: String) throws {
        requests = try UTR2Requests(address: address)
        let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 5; c.timeoutIntervalForResource = 10
        c.httpShouldSetCookies = false; c.httpCookieStorage = nil
        session = URLSession(configuration: c, delegate: RecorderSessionDelegate(), delegateQueue: nil)
    }
    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, !data.isEmpty, data.count < 1_048_576 else { throw RecorderError.invalidResponse }
        // Do not log this response: settings may contain the recorder's Wi-Fi credentials.
        let prefix = String(decoding: data.prefix(32), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !prefix.hasPrefix("error"), !prefix.hasPrefix("failed") else { throw RecorderError.rejected }
        return data
    }
    public func readSettings() async throws -> RecorderSnapshot {
        let snapshot = try JSONDecoder().decode(RecorderSnapshot.self, from: await perform(requests.settings()))
        guard snapshot.isUTR2 else { throw RecorderError.unsupportedRecorder }
        return snapshot
    }
    /// A successful request is not proof that the hardware clock was read back.
    public func sendDeviceClock(identity: RecorderSnapshot, date: Date = Date(), zone: TimeZone = .current) async throws {
        _ = try await perform(requests.clock(date: date, zone: zone, identity: identity))
    }
    public func updateSensors(driving: Int, parking: Int, radar: Int, identity: RecorderSnapshot) async throws -> RecorderSnapshot {
        _ = try await perform(requests.sensors(driving: driving, parking: parking, radar: radar, identity: identity))
        _ = try await perform(requests.saveSettings(identity: identity))
        let actual = try await readSettings()
        guard actual.drivingSensor == driving, actual.parkingSensor == parking, actual.radar == radar else { throw RecorderError.rejected }
        return actual
    }
}
