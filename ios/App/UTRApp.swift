import SwiftUI
import AVKit
import UniformTypeIdentifiers
import UTRCore

@main
struct UTRApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store).preferredColorScheme(.dark)
                .task { await store.foreground() }
                .onChange(of: phase) { _, value in if value == .active { Task { await store.foreground() } } }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in Task { await store.updateClockAutomatically() } }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in Task { await store.updateClockAutomatically() } }
        }
    }
}

enum AudiTheme {
    static let red = Color(red: 1, green: 45/255, blue: 0)
    static let background = Color(red: 18/255, green: 18/255, blue: 26/255)
    static let panel = Color(red: 27/255, green: 27/255, blue: 37/255)
}

struct Brand: View {
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: -6) { ForEach(0..<4) { _ in Circle().stroke(.white.opacity(0.9), lineWidth: 1.5).frame(width: 22, height: 22) } }.accessibilityLabel("Audi")
            Text("UTR").font(.system(size: 13, weight: .bold)).tracking(2)
        }.fixedSize(horizontal: true, vertical: false)
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var networkSheet = false
    var body: some View {
        TabView {
            NavigationStack { LiveView().toolbar { branding } }.tabItem { Label("Live", systemImage: "video") }
            NavigationStack { LibraryView().toolbar { branding } }.tabItem { Label("Library", systemImage: "rectangle.stack") }
            NavigationStack { RecorderView().toolbar { branding } }.tabItem { Label("Recorder", systemImage: "slider.horizontal.3") }
        }.tint(AudiTheme.red)
            .sheet(isPresented: $networkSheet) { NetworkSetupView() }
    }
    @ToolbarContentBuilder private var branding: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { Brand() }
        ToolbarItem(placement: .topBarTrailing) {
            Button { networkSheet = true } label: { Text(store.demo ? "DEMO / WI-FI" : "WI-FI").font(.system(size: 10, weight: .semibold)).tracking(1) }
                .accessibilityLabel("Recorder Wi-Fi setup")
        }
    }
}

struct Screen<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 3) { Rectangle().fill(AudiTheme.red); ForEach(0..<2) { _ in Rectangle().fill(.white.opacity(0.8)).frame(width: 14) } }.frame(height: 3)
                Text(title.uppercased()).font(.system(size: 32, weight: .black)).tracking(-1)
                content
            }.padding(.horizontal, 24).padding(.vertical, 18)
        }.background(AudiTheme.background)
    }
}

struct AutomaticClock: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Divider()
            HStack {
                Image(systemName: "clock").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Date & time").font(.subheadline.weight(.semibold))
                    Text("Uses your iPhone clock automatically.").font(.caption).foregroundStyle(.secondary)
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(context.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(TimeZone.current.identifier).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text("AUTO").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }.padding(.vertical, 7)
            if !store.demo { Text(store.clockState).font(.caption).foregroundStyle(.secondary) }
            Divider()
        }
    }
}

struct RoadPreview: View {
    let camera: Camera
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [.gray, Color(red: 0.7, green: 0.75, blue: 0.8)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color(red: 0.25, green: 0.3, blue: 0.27)).frame(height: g.size.height * 0.55).frame(maxHeight: .infinity, alignment: .bottom)
                Path { p in p.move(to: CGPoint(x: g.size.width * 0.47, y: g.size.height * 0.45)); p.addLine(to: CGPoint(x: g.size.width * 0.53, y: g.size.height * 0.45)); p.addLine(to: CGPoint(x: g.size.width, y: g.size.height)); p.addLine(to: CGPoint(x: 0, y: g.size.height)); p.closeSubpath() }.fill(Color(red: 0.27, green: 0.3, blue: 0.34))
                VStack(spacing: 12) { ForEach(0..<4) { _ in Rectangle().fill(.white.opacity(0.6)).frame(width: 3, height: 10) } }.position(x: g.size.width/2, y: g.size.height * 0.79)
                if camera == .rear { Image(systemName: "car.rear.fill").font(.system(size: g.size.width * 0.17)).foregroundStyle(.white.opacity(0.85)).position(x: g.size.width * 0.69, y: g.size.height * 0.75) }
                Text(camera.title.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(1).padding(6).background(.black.opacity(0.75)).clipShape(.rect(cornerRadius: 3)).padding(10)
            }.clipShape(.rect(cornerRadius: 5))
        }.accessibilityLabel("Illustrative \(camera.title) camera view")
    }
}

struct LiveView: View {
    @EnvironmentObject private var store: AppStore
    @State private var camera: Camera = .front
    @State private var paused = false
    var body: some View {
        Screen(title: "Live view") {
            Label(store.connection, systemImage: store.connected ? "wifi" : "wifi.slash").font(.caption).foregroundStyle(.secondary)
            Picker("Camera", selection: $camera) { Text("Front camera").tag(Camera.front); Text("Rear camera").tag(Camera.rear) }.pickerStyle(.segmented)
            if store.demo && store.connected {
                VStack(spacing: 0) {
                    RoadPreview(camera: camera).frame(height: 210)
                    HStack { Text(paused ? "Preview paused" : "Illustrative feed · \(camera.title)").font(.caption).foregroundStyle(.secondary); Spacer(); Button { paused.toggle() } label: { Image(systemName: paused ? "play" : "pause") }.accessibilityLabel(paused ? "Resume preview" : "Pause preview") }.padding(13).background(AudiTheme.panel)
                }
            } else {
                ContentUnavailableView(store.connected ? "Live video coming next" : "Recorder disconnected", systemImage: "video.slash", description: Text(store.connected ? "This first build can read settings and update the clock. RTSP video playback still needs integration." : "The app reconnects to your remembered Wi-Fi when you return to the recorder."))
            }
            AutomaticClock()
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if store.demo {
                Button(store.connected ? "Preview disconnected state" : "Preview connected state") { store.connected.toggle(); store.connection = store.connected ? "Connected · demo" : "Disconnected · demo" }.font(.caption)
                Text("Simulated connection · Illustrative footage").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var camera: Camera? = .front
    @State private var selected: Clip?
    @State private var importer = false
    @State private var recordedSort = false
    var shown: [Clip] {
        store.clips.filter { camera == nil || $0.camera == camera }.sorted {
            if recordedSort { return ($0.needsDateReview() ? "" : $0.effectiveTime ?? "") > ($1.needsDateReview() ? "" : $1.effectiveTime ?? "") }
            return $0.savedAt > $1.savedAt
        }
    }
    var body: some View {
        Screen(title: "Library") {
            HStack { Text("On iPhone").font(.subheadline.weight(.semibold)); Spacer(); Button { importer = true } label: { Label("Import", systemImage: "square.and.arrow.down") }.font(.caption) }
            Picker("Camera filter", selection: $camera) { Text("All").tag(Camera?.none); Text("Front").tag(Camera?.some(.front)); Text("Rear").tag(Camera?.some(.rear)) }.pickerStyle(.segmented)
            Toggle("Sort by recording date", isOn: $recordedSort).font(.caption)
            if shown.contains(where: { $0.needsDateReview() }) {
                Label("Some original dates need review. Automatic clock updates won’t change old clips.", systemImage: "calendar.badge.exclamationmark").font(.caption).foregroundStyle(.orange)
            }
            if shown.isEmpty { ContentUnavailableView("No saved clips", systemImage: "film", description: Text("Import videos from Files. Clips without a known camera appear under All.")) }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                ForEach(shown) { clip in
                    Button { selected = clip } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            if clip.isDemo { RoadPreview(camera: clip.camera).frame(height: 100) }
                            else { ZStack { AudiTheme.panel; Image(systemName: "play.rectangle").font(.largeTitle).foregroundStyle(.secondary) }.frame(height: 100).clipShape(.rect(cornerRadius: 5)) }
                            Text(clip.camera == .unknown ? "Imported clip" : "\(clip.camera.title) clip").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Text(clip.needsDateReview() ? "Date needs review" : String((clip.effectiveTime ?? "Unknown").prefix(16)).replacingOccurrences(of: "T", with: " ")).font(.caption2).foregroundStyle(clip.needsDateReview() ? .orange : .secondary)
                            Text("Saved \(clip.savedAt.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                }
            }
            if store.demo { Text("Sample clips · Import real videos using Files").font(.caption2).foregroundStyle(.secondary) }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
        .sheet(item: $selected) { ClipDetailView(initial: $0) }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie], allowsMultipleSelection: true) { result in
            switch result { case .success(let urls): camera = nil; Task { await store.importFiles(urls) }; case .failure(let error): store.error = error.localizedDescription }
        }
    }
}

struct ClipDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let initial: Clip
    @State private var camera = "front"
    @State private var position = 0.0
    @State private var editing = false
    @State private var correction = Date()
    @State private var player: AVPlayer?
    private var selected: Clip {
        let id = initial.isDemo ? (store.demoClips.first { $0.originalName.prefix(15) == initial.originalName.prefix(15) && $0.camera.rawValue == (camera == "both" ? "front" : camera) }?.id ?? initial.id) : initial.id
        return store.clips.first { $0.id == id } ?? initial
    }
    var body: some View {
        NavigationStack {
            Screen(title: "Recording") {
                if initial.isDemo {
                    Picker("Playback camera", selection: $camera) { Text("Front").tag("front"); Text("Rear").tag("rear"); Text("Both").tag("both") }.pickerStyle(.segmented)
                    if camera == "both" { RoadPreview(camera: .front).frame(height: 150); RoadPreview(camera: .rear).frame(height: 150) }
                    else { RoadPreview(camera: selected.camera).frame(height: 200) }
                    Slider(value: $position, in: 0...60).accessibilityLabel("Shared playback position")
                    Text("Matched sample clips · \(Int(position)) seconds").font(.caption).foregroundStyle(.secondary)
                } else if let player { VideoPlayer(player: player).frame(height: 220) }
                if selected.needsDateReview() { Label("Recording date is unverified", systemImage: "calendar.badge.exclamationmark").font(.caption).foregroundStyle(.orange) }
                fact("Recording date\(selected.correctedWallTime == nil ? " · from filename" : " · corrected by you")", selected.effectiveTime ?? "Unknown")
                fact("Saved to iPhone", selected.savedAt.formatted(date: .abbreviated, time: .shortened))
                fact("Original filename", selected.originalName)
                if selected.correctedWallTime != nil { fact("Original camera date · retained", selected.recordedWallTime ?? "Unknown") }
                if editing {
                    DatePicker("Correct recording date", selection: $correction, in: ...Date())
                    Text("Only this clip’s library label changes. The original video and other camera’s date stay intact.").font(.caption).foregroundStyle(.secondary)
                    Button("Save date in library") { store.correct(selected, date: correction); editing = false }.buttonStyle(.borderedProminent)
                    Button("Cancel", role: .cancel) { editing = false }
                } else { Button("Correct \(selected.camera.title.lowercased()) clip date") { editing = true } }
                if selected.correctedWallTime != nil { Button("Undo correction") { store.correct(selected, date: nil) } }
            }.toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.tint(AudiTheme.red)
            .onAppear { camera = initial.camera.rawValue; if let file = initial.localFile { player = AVPlayer(url: store.libraryDirectory.appending(path: file)) } }
            .onDisappear { player?.pause() }
    }
    private func fact(_ label: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 6) { Text(label).font(.caption).foregroundStyle(.secondary); Text(value.replacingOccurrences(of: "T", with: " ")).font(.subheadline); Divider() } }
}

struct RecorderView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Screen(title: "Recorder") {
            Text(store.connection).font(.caption).foregroundStyle(.secondary)
            AutomaticClock()
            if let network = store.network { Label(network.ssid, systemImage: "wifi").font(.caption); Text("Remembered on this iPhone. Password stored in Keychain.").font(.caption2).foregroundStyle(.secondary) }
            Text("SENSORS").font(.subheadline.weight(.bold)).tracking(1)
            sensor("Driving G-sensor", value: $store.driving, max: 5)
            sensor("Parking G-sensor", value: $store.parking, max: 5)
            sensor("Parking radar", value: $store.radar, max: 3)
            Button(store.demo ? "Preview settings" : "Apply sensor settings") { Task { await store.applySensors() } }.buttonStyle(.borderedProminent).disabled(store.busy || !store.connected)
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            if let snapshot = store.snapshot { Text("Firmware \(snapshot.firmware) · Hardware \(snapshot.hardware)").font(.caption2).foregroundStyle(.secondary) }
            Text("Legacy sensor ranges from APK V2.02. Hardware compatibility still needs testing.").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func sensor(_ title: String, value: Binding<Int>, max: Int) -> some View {
        HStack { Text(title).font(.subheadline); Spacer(); Picker(title, selection: value) { if value.wrappedValue > max { Text("Device: \(value.wrappedValue)").tag(value.wrappedValue) }; ForEach(0...max, id: \.self) { i in Text(i == 0 ? "Off" : String(i)).tag(i) } }.pickerStyle(.menu) }.disabled(!store.connected || store.busy)
    }
}

struct NetworkSetupView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var ssid = RecorderNetwork.saved?.ssid ?? ""
    @State private var address = RecorderNetwork.saved?.address ?? "192.168.1.1"
    @State private var password = ""
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Remember recorder Wi-Fi") {
                    TextField("Exact Wi-Fi name (SSID)", text: $ssid).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField(store.network?.ssid == ssid ? "Password saved · leave blank to keep" : "Wi-Fi password", text: $password).textContentType(.password)
                    Text("Enter this once. iOS remembers the network; the password stays in this iPhone’s Keychain.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Recorder address") { TextField("IPv4 address", text: $address).keyboardType(.decimalPad); Text("The default comes from the UTR reference app. Use the recorder access point, not the car’s internet hotspot.").font(.caption).foregroundStyle(.secondary) }
                Section {
                    Button(store.busy ? "Connecting…" : "Save and connect") { Task { do { try await store.saveNetwork(ssid: ssid, password: password, address: address); password = ""; dismiss() } catch { message = error.localizedDescription } } }.disabled(store.busy)
                    Button("Use Demo mode") { Task { await store.setDemo(true); dismiss() } }
                }
                if let message { Text(message).foregroundStyle(.orange) }
                Section { Text("iOS may ask before joining the first time. Date, time and timezone update automatically after the recorder is identified.").font(.caption) }
            }.navigationTitle("Recorder Wi-Fi").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }.tint(AudiTheme.red)
    }
}
