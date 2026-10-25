import SwiftUI
import Network
import UTRCore

@MainActor
final class AppStore: ObservableObject {
    @Published var demo = UserDefaults.standard.object(forKey: "demoMode") as? Bool ?? true
    @Published var connection = "Demo mode"
    @Published var connected = true
    @Published var busy = false
    @Published var network = RecorderNetwork.saved
    @Published var snapshot: RecorderSnapshot?
    @Published var error: String?
    @Published var clockState = "Automatic · Uses iPhone clock"
    @Published var driving = 2
    @Published var parking = 3
    @Published var radar = 3
    @Published var importedClips: [Clip] = []
    @Published var demoClips = Clip.demo
    private var client: RecorderClient?
    private let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private var attempt = UUID()
    private var clockBusy = false
    var clips: [Clip] { (importedClips + (demo ? demoClips : [])).sorted { $0.savedAt > $1.savedAt } }
    var libraryDirectory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Clips", directoryHint: .isDirectory) }
    private var indexURL: URL { libraryDirectory.appending(path: "library.json") }

    init() {
        if let data = try? Data(contentsOf: indexURL), let clips = try? JSONDecoder().decode([Clip].self, from: data) { importedClips = clips }
        connected = demo; connection = demo ? "Connected · demo" : "Disconnected"
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, !self.demo else { return }
                if available { await self.connect(allowJoin: false) }
                else { self.invalidateConnection() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "UTR.WiFi"))
    }
    func setDemo(_ value: Bool) async {
        invalidateConnection(); demo = value; UserDefaults.standard.set(value, forKey: "demoMode")
        if value { connected = true; connection = "Connected · demo"; clockState = "Automatic · Uses iPhone clock"; error = nil }
        else { await connect(allowJoin: true) }
    }
    func invalidateConnection() {
        attempt = UUID(); connected = false; snapshot = nil; client = nil; connection = "Disconnected"; clockState = "Automatic on connection"
    }
    func foreground() async {
        if !demo { await connect(allowJoin: true) }
    }
    func connect(allowJoin: Bool) async {
        guard !demo, !busy, let network else { return }
        busy = true; defer { busy = false }
        let token = UUID(); attempt = token; connected = false; snapshot = nil; client = nil; error = nil
        do {
            connection = "Joining remembered Wi-Fi…"
            if allowJoin { try await RememberedNetwork.join(network) }
            else if !(await RememberedNetwork.isCurrent(network)) { connection = "Waiting for recorder Wi-Fi"; return }
            guard token == attempt, !demo else { return }
            connection = "Checking recorder…"
            let next = try RecorderClient(address: network.address)
            // A joined Wi-Fi network alone is not a recorder connection. Read and identify
            // the device first, and recheck the SSID before allowing automatic writes.
            let identity = try await next.readSettings()
            guard token == attempt, !demo, await RememberedNetwork.isCurrent(network) else { return }
            client = next; snapshot = identity; connected = true; connection = "Connected"
            driving = identity.drivingSensor; parking = identity.parkingSensor; radar = identity.radar
            await updateClockAutomatically()
        } catch {
            guard token == attempt, !demo else { return }
            connection = "Recorder unavailable"; self.error = error.localizedDescription
        }
    }
    func updateClockAutomatically() async {
        // Called after identification and on system time/timezone changes; there is no
        // sync button. Success means the legacy request was accepted, not clock read-back.
        guard !demo, connected, !clockBusy, let client, let snapshot, let network else { return }
        clockBusy = true; defer { clockBusy = false }
        let token = attempt
        guard await RememberedNetwork.isCurrent(network) else { invalidateConnection(); return }
        do {
            try await client.sendDeviceClock(identity: snapshot, date: Date(), zone: .current)
            if token == attempt { clockState = "Phone time sent · verification pending" }
        } catch { if token == attempt { clockState = "Automatic clock update pending" } }
    }
    func applySensors() async {
        if demo { error = "Demo settings updated. Your recorder is unchanged."; return }
        guard connected, !busy, let client, let identity = snapshot, let network else { return }
        busy = true; defer { busy = false }; let token = attempt
        guard await RememberedNetwork.isCurrent(network) else { invalidateConnection(); return }
        do {
            let readBack = try await client.updateSensors(driving: driving, parking: parking, radar: radar, identity: identity)
            if token == attempt { snapshot = readBack; error = "Settings saved and read back from the recorder." }
        } catch { if token == attempt { self.error = error.localizedDescription } }
    }
    func saveNetwork(ssid: String, password: String, address: String) async throws {
        network = try RememberedNetwork.store(ssid: ssid, password: password, address: address)
        await setDemo(false)
    }
    func importFiles(_ urls: [URL]) async {
        do {
            try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
            for source in urls {
                let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                let filename = UUID().uuidString + "." + source.pathExtension.lowercased()
                let destination = libraryDirectory.appending(path: filename)
                try await Task.detached { try FileManager.default.copyItem(at: source, to: destination) }.value
                let name = source.lastPathComponent
                let cam: Camera = name.lowercased().contains("_front.") ? .front : name.lowercased().contains("_rear.") ? .rear : .unknown
                importedClips.append(Clip(name: name, camera: cam, localFile: filename))
                try persistLibrary()
            }
        } catch { self.error = "Could not finish importing: \(error.localizedDescription)" }
    }
    func correct(_ clip: Clip, date: Date?) {
        // Keep a correction in our catalog only. Do not rename or rewrite evidence files,
        // and do not propagate a guessed offset to clips from the other camera.
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        let corrected = date.map { formatter.string(from: $0) }
        if let i = importedClips.firstIndex(where: { $0.id == clip.id }) {
            let old = importedClips[i]; importedClips[i].correctedWallTime = corrected
            do { try persistLibrary() } catch { importedClips[i] = old; self.error = "The correction could not be saved." }
        } else if let i = demoClips.firstIndex(where: { $0.id == clip.id }) { demoClips[i].correctedWallTime = corrected }
    }
    private func persistLibrary() throws { try JSONEncoder().encode(importedClips).write(to: indexURL, options: .atomic) }
}
