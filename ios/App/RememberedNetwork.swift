import Foundation
import NetworkExtension
import Security
import UTRCore

struct RecorderNetwork: Codable, Equatable {
    var ssid: String
    var address: String
    static let preferenceKey = "rememberedRecorderNetwork"
    static var saved: Self? {
        guard let data = UserDefaults.standard.data(forKey: preferenceKey) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func save() throws { UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: Self.preferenceKey) }
}

enum WiFiSecret {
    // ThisDeviceOnly prevents iCloud/keychain migration of the recorder password.
    // The SSID is a preference; the password never enters UserDefaults or source files.
    private static let service = "com.sayantan.utrcompanion.recorderWiFi"
    private static func query(_ ssid: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: ssid]
    }
    static func save(_ password: String, ssid: String) throws {
        let attributes: [String: Any] = [kSecValueData as String: Data(password.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(ssid) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query(ssid).merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw NetworkSetupError.keychain }
        } else if status != errSecSuccess { throw NetworkSetupError.keychain }
    }
    static func read(ssid: String) throws -> String {
        var q = query(ssid); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data, let password = String(data: data, encoding: .utf8) else { throw NetworkSetupError.missingPassword }
        return password
    }
}

enum NetworkSetupError: Error, LocalizedError {
    case invalidSSID, invalidPassword, keychain, missingPassword, wrongNetwork, simulator
    var errorDescription: String? {
        switch self {
        case .invalidSSID: "Enter the exact recorder Wi-Fi name, up to 32 bytes."
        case .invalidPassword: "Enter its Wi-Fi password, 8–63 characters."
        case .keychain: "The password could not be saved securely."
        case .missingPassword: "Enter the recorder password once to save it securely."
        case .wrongNetwork: "The iPhone has not joined the remembered recorder network. Check that your recorder is nearby and powered on."
        case .simulator: "Wi-Fi joining needs a physical iPhone. Use Demo mode in the simulator."
        }
    }
}

@MainActor
enum RememberedNetwork {
    static func store(ssid: String, password: String, address: String) throws -> RecorderNetwork {
        guard !ssid.isEmpty, ssid.utf8.count <= 32 else { throw NetworkSetupError.invalidSSID }
        _ = try UTR2Requests(address: address)
        if password.isEmpty { _ = try WiFiSecret.read(ssid: ssid) }
        else {
            guard (8...63).contains(password.utf8.count) else { throw NetworkSetupError.invalidPassword }
            try WiFiSecret.save(password, ssid: ssid)
        }
        let network = RecorderNetwork(ssid: ssid, address: address); try network.save(); return network
    }
    static func isCurrent(_ network: RecorderNetwork) async -> Bool {
        await NEHotspotNetwork.fetchCurrent()?.ssid == network.ssid
    }
    static func join(_ network: RecorderNetwork) async throws {
        #if targetEnvironment(simulator)
        throw NetworkSetupError.simulator
        #else
        // Avoid repeating the iOS join prompt when the phone is already on the right AP.
        if await isCurrent(network) { return }
        let password = try WiFiSecret.read(ssid: network.ssid)
        let config = NEHotspotConfiguration(ssid: network.ssid, passphrase: password, isWEP: false)
        config.joinOnce = false // iOS keeps this network for subsequent auto-join.
        do { try await NEHotspotConfigurationManager.shared.apply(config) }
        catch let error as NSError where error.domain == NEHotspotConfigurationErrorDomain && error.code == NEHotspotConfigurationError.alreadyAssociated.rawValue { }
        for _ in 0..<5 {
            if await isCurrent(network) { return }
            try await Task.sleep(for: .seconds(1))
        }
        throw NetworkSetupError.wrongNetwork
        #endif
    }
}
