import SwiftUI
import Combine
import CoreBluetooth
import CryptoKit
import AVFoundation
import UserNotifications

// MARK: - Main App
@main
struct BuzzPairApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var fastPairManager = FastPairManager()
    @StateObject private var deviceManager = DeviceManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(fastPairManager)
                .environmentObject(deviceManager)
        }
        .windowStyle(HiddenTitleBarWindowStyle())
        .windowResizability(.contentSize)
        
        MenuBarExtra("BuzzPair", systemImage: "airpods") {
            MenuBarView()
                .environmentObject(fastPairManager)
                .environmentObject(deviceManager)
        }
    }
}

// MARK: - App Delegate
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request notification permissions
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

// MARK: - Fast Pair Models
struct FastPairDevice: Identifiable, Codable {
    let id: UUID
    let modelId: String
    let accountKey: Data
    let name: String
    let deviceType: DeviceType
    var batteryLevel: Int?
    var isConnected: Bool
    var connectionTime: Date?
    
    init(modelId: String, accountKey: Data, name: String, deviceType: DeviceType, batteryLevel: Int? = nil) {
        self.id = UUID()
        self.modelId = modelId
        self.accountKey = accountKey
        self.name = name
        self.deviceType = deviceType
        self.batteryLevel = batteryLevel
        self.isConnected = false
        self.connectionTime = nil
    }
    
    enum DeviceType: String, Codable, CaseIterable {
        case earbuds = "earbuds"
        case headphones = "headphones"
        case speaker = "speaker"
        
        var icon: String {
            switch self {
            case .earbuds: return "airpods"
            case .headphones: return "headphones"
            case .speaker: return "hifispeaker"
            }
        }
    }
}

struct AudioProfile: Codable, Equatable {
    let name: String
    let bassBoost: Float
    let trebleBoost: Float
    let midBoost: Float
}

enum ANCMode: String, CaseIterable {
    case off = "Off"
    case noiseCancellation = "Noise Cancellation"
    case transparency = "Transparency"
    
    var icon: String {
        switch self {
        case .off: return "speaker.wave.1"
        case .noiseCancellation: return "speaker.slash"
        case .transparency: return "speaker.wave.3"
        }
    }
}

// MARK: - Fast Pair ManageR
class FastPairManager: NSObject, ObservableObject {
    @Published var discoveredDevices: [FastPairDevice] = []
    @Published var isScanning = false
    @Published var bluetoothState: CBManagerState = .unknown
    private func extractModelId(from fastPairData: Data) -> String {
        // The Model ID is a 24-bit (3-byte) unsigned integer at the beginning of the service data.
        guard fastPairData.count >= 3 else {
            print("Warning: Fast Pair data too short to extract Model ID. Data count: \(fastPairData.count)")
            return "000000" // Default or error value
        }

        // Extract the first 3 bytes
        let modelIdBytes = fastPairData.prefix(3)

        // Convert 3 bytes to a UInt32 (assuming big-endian, common in BLE)
        // Pad with a leading zero byte to make it 4 bytes for UInt32 conversion
        var modelId: UInt32 = 0
        // Use withUnsafeBytes to directly copy bytes, ensuring correct endianness if necessary.
        // For a 24-bit ID, it's typically read as a 3-byte value. If direct UInt32, assume big-endian.
        // Here, we manually combine the bytes for clarity and explicit big-endian interpretation.
        modelId = UInt32(modelIdBytes[0]) << 16 | UInt32(modelIdBytes[1]) << 8 | UInt32(modelIdBytes[2])

        // Format as a 6-character hexadecimal string
        return String(format: "%06X", modelId)
    }

    
    private var centralManager: CBCentralManager!
    private var discoveredPeripherals: [CBPeripheral] = []
    private let fastPairServiceUUID = CBUUID(string: "FE2C")
    
    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    func startScanning() {
        guard bluetoothState == .poweredOn else {
            print("Bluetooth not powered on. Current state: \(bluetoothState)")
            return
        }
        
        print("Starting Fast Pair scan...")
        isScanning = true
        
        // Scan for all devices first, then filter for Fast Pair compatible ones
        centralManager.scanForPeripherals(
            withServices: nil, // Scan for all devices to catch Fast Pair devices
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: true,
                CBCentralManagerScanOptionSolicitedServiceUUIDsKey: [fastPairServiceUUID]
            ]
        )
        
        // Stop scanning after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            self.stopScanning()
        }
    }
    
    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }
    
    func connectToDevice(_ device: FastPairDevice) {
        // Find the peripheral for this device
        if let peripheral = discoveredPeripherals.first(where: { $0.name == device.name }) {
            centralManager.connect(peripheral, options: nil)
        }
    }
    
    
    private func processAdvertisementData(_ advertisementData: [String: Any], peripheral: CBPeripheral) -> FastPairDevice? {
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let fastPairData = serviceData[fastPairServiceUUID] else {
            return nil
        }
        
        // Parse Fast Pair advertisement data
        let modelId = extractModelId(from: fastPairData)
        let accountKey = generateAccountKey()
        
        return FastPairDevice(
            modelId: modelId,
            accountKey: accountKey,
            name: peripheral.name ?? "Unknown Device",
            deviceType: determineDeviceType(from: peripheral.name ?? "")
        )
    }
    
    private func generateAccountKey() -> Data {
        // Generate account key using CryptoKit
        let key = SymmetricKey(size: .bits256)
        return key.withUnsafeBytes { Data($0) }
    }
    
    private func determineDeviceType(from name: String) -> FastPairDevice.DeviceType {
        let lowercaseName = name.lowercased()
        if lowercaseName.contains("buds") || lowercaseName.contains("pods") {
            return .earbuds
        } else if lowercaseName.contains("headphones") || lowercaseName.contains("headset") {
            return .headphones
        } else {
            return .speaker
        }
    }
    
    private func sendNotification(for device: FastPairDevice) {
        let content = UNMutableNotificationContent()
        content.title = "Fast Pair Device Found"
        content.body = "\(device.name) is ready to connect"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: device.id.uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Core Bluetooth Delegate
extension FastPairManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            self.bluetoothState = central.state
            print("Bluetooth state changed to: \(central.state.rawValue)")
            
            switch central.state {
            case .poweredOn:
                print("Bluetooth is powered on and ready")
                // Auto-start scanning when Bluetooth becomes available
                if !self.isScanning {
                    self.startScanning()
                }
            case .poweredOff:
                print("Bluetooth is powered off")
                self.isScanning = false
                self.discoveredDevices.removeAll()
                self.discoveredPeripherals.removeAll()
            case .unauthorized:
                print("Bluetooth access not authorized")
            case .unsupported:
                print("Bluetooth not supported on this device")
            default:
                print("Bluetooth state: \(central.state)")
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        
        print("Discovered device: \(peripheral.name ?? "Unknown") - RSSI: \(RSSI)")
        print("Advertisement data: \(advertisementData)")
        
        // Check if this is a potential Fast Pair device
        let isFastPairCandidate = checkIfFastPairCandidate(peripheral: peripheral, advertisementData: advertisementData)
        
        if isFastPairCandidate {
            guard !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) else { return }
            
            let device = createFastPairDevice(from: peripheral, advertisementData: advertisementData)
            
            DispatchQueue.main.async {
                self.discoveredDevices.append(device)
                self.discoveredPeripherals.append(peripheral)
                self.sendNotification(for: device)
            }
        }
    }
    
    private func checkIfFastPairCandidate(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        // Check for Fast Pair service UUID in advertisement
        if let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            if serviceUUIDs.contains(fastPairServiceUUID) {
                return true
            }
        }
        
        // Check for Fast Pair service data
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            if serviceData[fastPairServiceUUID] != nil {
                return true
            }
        }
        
        // Check device name patterns for known Fast Pair compatible devices
//        if let deviceName = peripheral.name?.lowercased() {
//            let fastPairPatterns = [
//                "pixel buds", "pixelbuds",
//                "wh-1000xm", "wf-1000xm", "linkbuds",
//                "quietcomfort", "bose",
//                "jbl", "flip", "charge",
//                "galaxy buds", "gear icon"
//            ]
//
//            for pattern in fastPairPatterns {
//                if deviceName.contains(pattern) {
//                    return true
//                }
//            }
//        }
        
        // Check manufacturer data for Google's company identifier (0x00E0)
        if let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            if manufacturerData.count >= 2 {
                let companyId = manufacturerData.prefix(2).withUnsafeBytes { $0.load(as: UInt16.self) }
                if companyId == 0x00E0 { // Google's Bluetooth SIG company ID
                    return true
                }
            }
        }
        
        return false
    }
    
    private func createFastPairDevice(from peripheral: CBPeripheral, advertisementData: [String: Any]) -> FastPairDevice {
        // Correctly extract the fastPairData first
        guard let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let fastPairData = serviceData[fastPairServiceUUID] else {
            // Handle case where Fast Pair data is missing (e.g., return a default device or nil)
            print("Error: Could not extract Fast Pair service data for device \(peripheral.name ?? "Unknown")")
            // You might want to return an optional FastPairDevice or a default one
            // For simplicity, returning a default and logging. You might refine this.
            return FastPairDevice(modelId: "ERROR", accountKey: generateAccountKey(), name: peripheral.name ?? "Unknown Device", deviceType: .speaker)
        }

        let modelId = extractModelId(from: fastPairData) // <--- THIS IS CORRECT NOW
        let accountKey = generateAccountKey()
        let deviceName = peripheral.name ?? "Unknown Fast Pair Device"
        let deviceType = determineDeviceType(from: deviceName)

        return FastPairDevice(
            modelId: modelId,
            accountKey: accountKey,
            name: deviceName,
            deviceType: deviceType
        )
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Handle successful connection
        if let index = discoveredDevices.firstIndex(where: { $0.name == peripheral.name }) {
            discoveredDevices[index].isConnected = true
            discoveredDevices[index].connectionTime = Date()
        }
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("Failed to connect to \(peripheral.name ?? "Unknown"): \(error?.localizedDescription ?? "Unknown error")")
    }
}

// MARK: - Device Manager
class DeviceManager: ObservableObject {
    @Published var connectedDevices: [FastPairDevice] = []
    @Published var currentVolume: Float = 0.5
    @Published var currentANCMode: ANCMode = .off
    @Published var selectedAudioProfile = AudioProfile(name: "Balanced", bassBoost: 0, trebleBoost: 0, midBoost: 0)
    
    private var audioEngine = AVAudioEngine()
    private var audioUnit: AVAudioUnit?
    
    let audioProfiles = [
        AudioProfile(name: "Balanced", bassBoost: 0, trebleBoost: 0, midBoost: 0),
        AudioProfile(name: "Bass Boost", bassBoost: 0.3, trebleBoost: 0, midBoost: 0),
        AudioProfile(name: "Vocal", bassBoost: -0.1, trebleBoost: 0.2, midBoost: 0.3),
        AudioProfile(name: "Treble Boost", bassBoost: 0, trebleBoost: 0.3, midBoost: 0)
    ]
    
    func setVolume(_ volume: Float) {
        currentVolume = volume
        // Apply volume to connected devices
        applyVolumeToDevices()
    }
    
    func setANCMode(_ mode: ANCMode) {
        currentANCMode = mode
        // Send ANC command to connected devices
        applyANCModeToDevices()
    }
    
    func setAudioProfile(_ profile: AudioProfile) {
        selectedAudioProfile = profile
        // Apply EQ settings
        applyEQSettings()
    }
    
    private func applyVolumeToDevices() {
        // Implementation for applying volume to Fast Pair devices
        // This would involve sending the appropriate Bluetooth commands
    }
    
    private func applyANCModeToDevices() {
        // Implementation for toggling ANC modes
        // This involves sending specific Fast Pair protocol commands
    }
    
    private func applyEQSettings() {
        // Implementation for applying EQ settings
        // This would configure the audio engine with the selected profile
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @EnvironmentObject var fastPairManager: FastPairManager
    @EnvironmentObject var deviceManager: DeviceManager
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                HeaderView()
                
                TabView(selection: $selectedTab) {
                    DevicesView()
                        .tabItem {
                            Image(systemName: "airpods")
                            Text("Devices")
                        }
                        .tag(0)
                    
                    ControlsView()
                        .tabItem {
                            Image(systemName: "slider.horizontal.3")
                            Text("Controls")
                        }
                        .tag(1)
                    
                    SettingsView()
                        .tabItem {
                            Image(systemName: "gear")
                            Text("Settings")
                        }
                        .tag(2)
                }
            }
        }
        .frame(width: 400, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Header View
struct HeaderView: View {
    @EnvironmentObject var fastPairManager: FastPairManager
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("BuzzPair")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Fast Pair for macOS")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                if fastPairManager.isScanning {
                    fastPairManager.stopScanning()
                } else {
                    fastPairManager.startScanning()
                }
            }) {
                Image(systemName: fastPairManager.isScanning ? "stop.circle" : "magnifyingglass")
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct DevicesView: View {
    @EnvironmentObject var fastPairManager: FastPairManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Available Devices")
                    .font(.headline)
                
                Spacer()
                
                Text("Bluetooth: \(bluetoothStatusText)")
                    .font(.caption)
                    .foregroundColor(bluetoothStatusColor)
            }
            .padding(.horizontal)
            
            if fastPairManager.discoveredDevices.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: fastPairManager.isScanning ? "antenna.radiowaves.left.and.right" : "airpods")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                        .symbolEffect(.pulse, options: .repeating, isActive: fastPairManager.isScanning)
                    
                    Text(fastPairManager.isScanning ? "Searching for devices..." : "No devices found")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        Text("To find Fast Pair devices:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("1. Put your earbuds/headphones in pairing mode")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("2. Make sure they're Fast Pair compatible")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("3. Click the search button above")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(fastPairManager.discoveredDevices) { device in
                            DeviceCardView(device: device)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private var bluetoothStatusText: String {
        switch fastPairManager.bluetoothState {
        case .poweredOn: return "On"
        case .poweredOff: return "Off"
        case .unauthorized: return "Unauthorized"
        case .unsupported: return "Unsupported"
        case .resetting: return "Resetting"
        default: return "Unknown"
        }
    }
    
    private var bluetoothStatusColor: Color {
        switch fastPairManager.bluetoothState {
        case .poweredOn: return .green
        case .poweredOff: return .red
        case .unauthorized: return .orange
        default: return .secondary
        }
    }
}

// MARK: - Device Card View
struct DeviceCardView: View {
    let device: FastPairDevice
    @EnvironmentObject var fastPairManager: FastPairManager
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: device.deviceType.icon)
                .font(.system(size: 24))
                .foregroundColor(.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                
                Text(device.deviceType.rawValue.capitalized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let batteryLevel = device.batteryLevel {
                    HStack(spacing: 4) {
                        Image(systemName: "battery.\(batteryLevel > 75 ? "100" : batteryLevel > 50 ? "75" : batteryLevel > 25 ? "50" : "25")")
                            .foregroundColor(batteryLevel > 25 ? .green : .orange)
                        Text("\(batteryLevel)%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Button(device.isConnected ? "Disconnect" : "Connect") {
                if device.isConnected {
                    // Disconnect logic
                } else {
                    fastPairManager.connectToDevice(device)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Controls View
struct ControlsView: View {
    @EnvironmentObject var deviceManager: DeviceManager
    
    var body: some View {
        VStack(spacing: 24) {
            Text("Audio Controls")
                .font(.headline)
            
            // Volume Control
            VStack(alignment: .leading, spacing: 8) {
                Text("Volume")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundColor(.secondary)
                    
                    Slider(value: Binding(
                        get: { deviceManager.currentVolume },
                        set: { deviceManager.setVolume($0) }
                    ), in: 0...1)
                    
                    Image(systemName: "speaker.3.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            // ANC Mode Control
            VStack(alignment: .leading, spacing: 8) {
                Text("Active Noise Control")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("ANC Mode", selection: Binding(
                    get: { deviceManager.currentANCMode },
                    set: { deviceManager.setANCMode($0) }
                )) {
                    ForEach(ANCMode.allCases, id: \.self) { mode in
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            // Audio Profile Control
            VStack(alignment: .leading, spacing: 8) {
                Text("Audio Profile")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("Audio Profile", selection: Binding(
                    get: { deviceManager.selectedAudioProfile.name },
                    set: { profileName in
                        if let profile = deviceManager.audioProfiles.first(where: { $0.name == profileName }) {
                            deviceManager.setAudioProfile(profile)
                        }
                    }
                )) {
                    ForEach(deviceManager.audioProfiles.map(\.name), id: \.self) { profileName in
                        Text(profileName).tag(profileName)
                    }
                }
                .pickerStyle(.menu)
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @State private var showNotifications = true
    @State private var autoConnect = true
    @State private var batteryAlerts = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Settings")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Show Notifications", isOn: $showNotifications)
                Toggle("Auto-connect to known devices", isOn: $autoConnect)
                Toggle("Battery level alerts", isOn: $batteryAlerts)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("About")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("BuzzPair v1.0.0")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("Developed by Dhruv Chhabra")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Link("GitHub Repository", destination: URL(string: "https://github.com/chhabraadhruv/buzzpair")!)
                    .font(.caption)
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Menu Bar View
struct MenuBarView: View {
    @EnvironmentObject var fastPairManager: FastPairManager
    @EnvironmentObject var deviceManager: DeviceManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BuzzPair")
                .font(.headline)
                .padding(.horizontal)
            
            Divider()
            
            if deviceManager.connectedDevices.isEmpty {
                Text("No devices connected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            } else {
                ForEach(deviceManager.connectedDevices) { device in
                    HStack {
                        Image(systemName: device.deviceType.icon)
                            .foregroundColor(.accentColor)
                        
                        Text(device.name)
                            .font(.caption)
                        
                        Spacer()
                        
                        if let batteryLevel = device.batteryLevel {
                            Text("\(batteryLevel)%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            Divider()
            
            Button("Open BuzzPair") {
                NSApp.activate(ignoringOtherApps: true)
            }
            .padding(.horizontal)
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal)
        }
        .frame(width: 200)
    }
}

// MARK: - Crypto Extensions
extension Data {
    func aesEncrypt(key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(self, using: key)
        return sealedBox.combined ?? Data()
    }
    
    func aesDecrypt(key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: self)
        return try AES.GCM.open(sealedBox, using: key)
    }
}

// MARK: - Fast Pair Crypto Helper
class FastPairCrypto {
    static func deriveSharedSecret(privateKey: P256.KeyAgreement.PrivateKey, publicKey: P256.KeyAgreement.PublicKey) throws -> SharedSecret {
        return try privateKey.sharedSecretFromKeyAgreement(with: publicKey)
    }
    
    static func generateKeyPair() -> P256.KeyAgreement.PrivateKey {
        return P256.KeyAgreement.PrivateKey()
    }
    
    static func performHandshake(with devicePublicKey: Data) throws -> (SymmetricKey, Data) {
        let privateKey = generateKeyPair()
        let publicKey = privateKey.publicKey
        
        let deviceKey = try P256.KeyAgreement.PublicKey(rawRepresentation: devicePublicKey)
        let sharedSecret = try deriveSharedSecret(privateKey: privateKey, publicKey: deviceKey)
        
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data(),
            sharedInfo: Data(),
            outputByteCount: 32
        )
        
        return (symmetricKey, publicKey.rawRepresentation)
    }
}
