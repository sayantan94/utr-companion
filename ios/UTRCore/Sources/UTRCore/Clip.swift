import Foundation

public struct Clip: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var originalName: String
    public var camera: Camera
    public var recordedWallTime: String?
    public var correctedWallTime: String?
    public var savedAt: Date
    public var localFile: String?
    public var isDemo: Bool
    public var effectiveTime: String? { correctedWallTime ?? recordedWallTime }
    public init(name: String, camera: Camera = .unknown, savedAt: Date = Date(), localFile: String? = nil, isDemo: Bool = false) {
        id = UUID(); originalName = name; self.camera = camera; self.savedAt = savedAt; self.localFile = localFile; self.isDemo = isDemo
        recordedWallTime = Self.filenameTime(name)
    }
    /// A filename supplies wall-clock components, not a verified instant or timezone.
    public static func filenameTime(_ name: String) -> String? {
        guard name.range(of: #"^\d{8}_\d{6}"#, options: .regularExpression) != nil else { return nil }
        let raw = String(name.prefix(15))
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(secondsFromGMT: 0); f.isLenient = false; f.dateFormat = "yyyyMMdd_HHmmss"
        guard let date = f.date(from: raw), f.string(from: date) == raw else { return nil }
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; return f.string(from: date)
    }
    public func needsDateReview(now: Date = Date(), zone: TimeZone = .current) -> Bool {
        guard let recorded = effectiveTime else { return true }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian); f.timeZone = zone; f.dateFormat = "yyyy-MM-dd"
        return String(recorded.prefix(10)) > f.string(from: now)
    }
    public static var demo: [Clip] {
        ["20310401_101936", "20261025_091800", "20310403_174206", "20261024_171500"].flatMap { stem in
            [Camera.front, .rear].map { Clip(name: "\(stem)_\($0.rawValue).MP4", camera: $0, isDemo: true) }
        }
    }
}
