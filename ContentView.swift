import SwiftUI
import CoreBluetooth
import CryptoKit
import UserNotifications
import AVFoundation

// MARK: - Models
struct FastPairDevice: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let peripheral: CBPeripheral
    let rssi: NSNumber
    let modelId: String
    var isConnected: Bool = false
    var batteryLevel: Int? = nil
    var ancMode: ANCMode = .off
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: FastPairDevice, rhs: FastPairDevice) -> Bool {
        lhs.id == rhs.id
    }
}

enum ANCMode: String, CaseIterable {
    case noiseCancellation = "Noise Cancellation"
    case transparency = "Transparency"
    case off = "Off"
    
    var icon: String {
        switch self {
        case .noiseCancellation: return "noise.reducer"
        case .transparency: return "transparency"
        case .off: return "speaker.slash"
        }
    }
}

enum EQPreset: String, CaseIterable {
    case balanced = "Balanced"
    case bass = "Bass Boost"
    case treble = "Treble Boost"
    case vocal = "Vocal"
    case rock = "Rock"
    case jazz = "Jazz"
    
    var icon: String {
        switch self {
        case .balanced: return "music.note"
        case .bass: return "waveform.path.badge.plus"
        case .treble: return "waveform.path.ecg"
        case .vocal: return "mic"
        case .rock: return "guitars"
        case .jazz: return "music.quarternote.3"
        }
    }
}

// MARK: - Google Fast Pair Service
class GoogleFastPairService: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    // Google Fast Pair Service UUID
    private let fastPairServiceUUID = CBUUID(string: "FE2C")
    private let modelIdCharacteristicUUID = CBUUID(string: "1233")
    private let keyBasedPairingCharacteristicUUID = CBUUID(string: "1234")
    private let passphroughCharacteristicUUID = CBUUID(string: "1235")
    private let accountKeyCharacteristicUUID = CBUUID(string: "1236")
    
    private var centralManager: CBCentralManager?
    private var discoveredPeripherals: [CBPeripheral] = []
    private var connectedPeripheral: CBPeripheral?
    
    @Published var discoveredDevices: [FastPairDevice] = []
    @Published var connectedDevice: FastPairDevice?
    @Published var isScanning = false
    @Published var connectionStatus = "Ready to scan"
    @Published var isBluetoothReady = false
    
    // Known Fast Pair Model IDs (in real implementation, these would come from Google's registry)
    private let knownModelIds: [String: String] = [
        "0x72CF9C": "Pixel Buds Pro",
        "0x0001F0": "Sony WH-1000XM4",
        "0x0A1710": "Bose QuietComfort Earbuds",
        "0x0E30C3": "JBL Live Pro+",
        "0x92BBBD": "Pixel Buds A-Series"
    ]
    
    override init() {
        super.init()
        requestNotificationPermission()
        
        // Check system compatibility first
        checkSystemCompatibility()
        
        // Delay initialization to ensure proper setup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Initialize with minimal options first
            self.centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main, options: nil)
        }
    }
    
    private func checkSystemCompatibility() {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        print("🖥️ macOS Version: \(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)")
        
        if osVersion.majorVersion < 12 {
            print("⚠️ Warning: BuzzPair requires macOS 12.0 or later")
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func startScanning() {
        guard let centralManager = centralManager else {
            connectionStatus = "Bluetooth manager not initialized"
            return
        }
        
        guard centralManager.state == .poweredOn else {
            connectionStatus = "Bluetooth not ready: \(centralManager.state)"
            return
        }
        
        isScanning = true
        connectionStatus = "Scanning for Fast Pair devices..."
        discoveredDevices.removeAll()
        
        // First scan for Fast Pair service
        centralManager.scanForPeripherals(withServices: [fastPairServiceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
        
        // Also scan for devices without service filter to catch more devices
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if self.isScanning && self.discoveredDevices.isEmpty {
                print("🔍 Expanding search to all devices...")
                centralManager.scanForPeripherals(withServices: nil, options: [
                    CBCentralManagerScanOptionAllowDuplicatesKey: false
                ])
            }
        }
        
        // Stop scanning after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            self.stopScanning()
        }
    }
    
    func stopScanning() {
        centralManager?.stopScan()
        isScanning = false
        if discoveredDevices.isEmpty {
            connectionStatus = "No Fast Pair devices found"
        } else {
            connectionStatus = "Found \(discoveredDevices.count) device(s)"
        }
    }
    
    func connect(to device: FastPairDevice) {
        guard let centralManager = centralManager else { return }
        
        connectionStatus = "Connecting to \(device.name)..."
        centralManager.connect(device.peripheral, options: nil)
    }
    
    func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        centralManager?.cancelPeripheralConnection(peripheral)
    }
    
    private func performFastPairHandshake(with peripheral: CBPeripheral) {
        // Discover Fast Pair service
        peripheral.discoverServices([fastPairServiceUUID])
    }
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - CBCentralManagerDelegate
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        DispatchQueue.main.async {
            switch central.state {
            case .poweredOn:
                self.connectionStatus = "Bluetooth ready"
                self.isBluetoothReady = true
                print("✅ Bluetooth is powered on and ready")
            case .poweredOff:
                self.connectionStatus = "Bluetooth is off - Please turn on Bluetooth"
                self.isBluetoothReady = false
                print("❌ Bluetooth is powered off")
            case .unauthorized:
                self.connectionStatus = "Bluetooth access denied - Check Privacy settings"
                self.isBluetoothReady = false
                print("❌ Bluetooth unauthorized")
            case .unsupported:
                self.connectionStatus = "Bluetooth LE not supported on this Mac"
                self.isBluetoothReady = false
                print("❌ Bluetooth LE unsupported")
            case .unknown:
                self.connectionStatus = "Bluetooth state unknown - Checking..."
                self.isBluetoothReady = false
                print("⚠️ Bluetooth state unknown")
            case .resetting:
                self.connectionStatus = "Bluetooth is resetting..."
                self.isBluetoothReady = false
                print("🔄 Bluetooth resetting")
            @unknown default:
                self.connectionStatus = "Unknown Bluetooth state"
                self.isBluetoothReady = false
                print("❓ Unknown Bluetooth state: \(central.state.rawValue)")
            }
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        print("🔍 Discovered device: \(peripheral.name ?? "Unknown") - RSSI: \(RSSI)")
        print("📡 Advertisement data: \(advertisementData)")
        
        // Check if this is a Fast Pair device
        var isFastPairDevice = false
        var modelId = "0x000000"
        var deviceName = peripheral.name ?? "Unknown Device"
        
        // Check for Fast Pair service data
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
           let fastPairData = serviceData[fastPairServiceUUID] {
            modelId = extractModelId(from: fastPairData)
            deviceName = knownModelIds[modelId] ?? deviceName
            isFastPairDevice = true
            print("✅ Fast Pair device detected with Model ID: \(modelId)")
        }
        
        // Also check for known device names that might support Fast Pair
        let fastPairKeywords = ["buds", "pixel", "sony", "bose", "jbl", "earbuds", "headphones"]
        let nameContainsFastPairKeyword = fastPairKeywords.contains { keyword in
            deviceName.lowercased().contains(keyword)
        }
        
        if isFastPairDevice || nameContainsFastPairKeyword {
            let device = FastPairDevice(
                name: deviceName,
                peripheral: peripheral,
                rssi: RSSI,
                modelId: modelId
            )
            
            if !discoveredDevices.contains(device) {
                DispatchQueue.main.async {
                    self.discoveredDevices.append(device)
                    print("➕ Added device: \(deviceName)")
                    
                    // Send notification for nearby device
                    self.sendNotification(
                        title: "Fast Pair Device Found",
                        body: "\(deviceName) is ready to connect"
                    )
                }
            }
        } else {
            print("ℹ️ Device \(deviceName) doesn't appear to support Fast Pair")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        connectedPeripheral = peripheral
        
        if let deviceIndex = discoveredDevices.firstIndex(where: { $0.peripheral == peripheral }) {
            discoveredDevices[deviceIndex].isConnected = true
            connectedDevice = discoveredDevices[deviceIndex]
        }
        
        connectionStatus = "Connected to \(peripheral.name ?? "device")"
        performFastPairHandshake(with: peripheral)
        
        sendNotification(
            title: "Device Connected",
            body: "\(peripheral.name ?? "Your device") is now connected"
        )
    }
    
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedPeripheral = nil
        connectedDevice = nil
        
        if let deviceIndex = discoveredDevices.firstIndex(where: { $0.peripheral == peripheral }) {
            discoveredDevices[deviceIndex].isConnected = false
        }
        
        connectionStatus = "Disconnected"
    }
    
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionStatus = "Failed to connect: \(error?.localizedDescription ?? "Unknown error")"
    }
    
    // MARK: - CBPeripheralDelegate
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        
        for service in services where service.uuid == fastPairServiceUUID {
            peripheral.discoverCharacteristics([
                modelIdCharacteristicUUID,
                keyBasedPairingCharacteristicUUID,
                passphroughCharacteristicUUID,
                accountKeyCharacteristicUUID
            ], for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            switch characteristic.uuid {
            case keyBasedPairingCharacteristicUUID:
                performKeyBasedPairing(peripheral: peripheral, characteristic: characteristic)
            default:
                break
            }
        }
    }
    
    // MARK: - Fast Pair Crypto Implementation
    private func extractModelId(from data: Data) -> String {
        // Extract model ID from Fast Pair advertisement data
        if data.count >= 3 {
            let modelIdBytes = data.subdata(in: 0..<3)
            return "0x" + modelIdBytes.map { String(format: "%02X", $0) }.joined()
        }
        return "0x000000"
    }
    
    private func performKeyBasedPairing(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        // Generate key pair for pairing
        let privateKey = P256.KeyAgreement.PrivateKey()
        let publicKeyData = privateKey.publicKey.rawRepresentation
        
        // Create pairing request (simplified implementation)
        var pairingRequest = Data()
        pairingRequest.append(0x00) // Key-based pairing type
        pairingRequest.append(publicKeyData)
        
        // Write pairing request
        peripheral.writeValue(pairingRequest, for: characteristic, type: .withResponse)
    }
    
    // MARK: - Device Controls
    func toggleANCMode(for device: FastPairDevice) {
        guard let peripheral = connectedPeripheral else { return }
        
        let newMode: ANCMode
        switch device.ancMode {
        case .off:
            newMode = .noiseCancellation
        case .noiseCancellation:
            newMode = .transparency
        case .transparency:
            newMode = .off
        }
        
        // Update local state
        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index].ancMode = newMode
            connectedDevice?.ancMode = newMode
        }
        
        // Send ANC command to device (implementation would depend on device protocol)
        sendANCCommand(peripheral: peripheral, mode: newMode)
    }
    
    private func sendANCCommand(peripheral: CBPeripheral, mode: ANCMode) {
        // This would send the actual ANC command to the device
        // Implementation depends on the specific device protocol
        print("Setting ANC mode to: \(mode.rawValue)")
    }
    
    func updateVolume(_ volume: Double) {
        // Update system volume or send volume command to device
        let volumeScript = """
            set volume output volume \(Int(volume * 100))
        """
        
        if let script = NSAppleScript(source: volumeScript) {
            script.executeAndReturnError(nil)
        }
    }
    
    func setEQPreset(_ preset: EQPreset) {
        guard let peripheral = connectedPeripheral else { return }
        
        // Send EQ preset command to device
        sendEQCommand(peripheral: peripheral, preset: preset)
    }
    
    private func sendEQCommand(peripheral: CBPeripheral, preset: EQPreset) {
        // This would send the actual EQ command to the device
        print("Setting EQ preset to: \(preset.rawValue)")
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var fastPairService = GoogleFastPairService()
    @State private var volume: Double = 0.5
    @State private var selectedEQPreset: EQPreset = .balanced
    @State private var showingDeviceDetails = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                headerView
                
                // Connection Status
                statusView
                
                // Device List
                deviceListView
                
                // Connected Device Controls
                if let connectedDevice = fastPairService.connectedDevice {
                    connectedDeviceView(connectedDevice)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("BuzzPair")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    scanButton
                }
            }
        }
        .frame(minWidth: 400, minHeight: 600)
    }
    
    private var headerView: some View {
        VStack {
            Image(systemName: "headphones")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("BuzzPair")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Google Fast Pair for macOS")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var statusView: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(fastPairService.isScanning ? Color.orange : (fastPairService.connectedDevice != nil ? Color.green : (fastPairService.isBluetoothReady ? Color.blue : Color.red)))
                    .frame(width: 8, height: 8)
                
                Text(fastPairService.connectionStatus)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Debug info
            if !fastPairService.isBluetoothReady {
                Text("💡 Tip: Make sure Bluetooth is enabled and BuzzPair has permission")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }
    
    private var deviceListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !fastPairService.discoveredDevices.isEmpty {
                Text("Discovered Devices")
                    .font(.headline)
                    .padding(.leading)
                
                LazyVStack(spacing: 8) {
                    ForEach(fastPairService.discoveredDevices) { device in
                        deviceRow(device)
                    }
                }
            }
        }
    }
    
    private func deviceRow(_ device: FastPairDevice) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                
                HStack {
                    Text("RSSI: \(device.rssi)dBm")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let battery = device.batteryLevel {
                        Text("Battery: \(battery)%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if device.isConnected {
                Button("Disconnect") {
                    fastPairService.disconnect()
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button("Connect") {
                    fastPairService.connect(to: device)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(device.isConnected ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func connectedDeviceView(_ device: FastPairDevice) -> some View {
        VStack(spacing: 16) {
            Text("Connected Device Controls")
                .font(.headline)
            
            // ANC Controls
            GroupBox("Noise Control") {
                HStack {
                    ForEach(ANCMode.allCases, id: \.self) { mode in
                        Button(action: {
                            fastPairService.toggleANCMode(for: device)
                        }) {
                            VStack {
                                Image(systemName: mode.icon)
                                    .font(.title2)
                                Text(mode.rawValue)
                                    .font(.caption)
                            }
                            .foregroundColor(device.ancMode == mode ? .white : .primary)
                        }
                        .buttonStyle(.bordered)
                        .background(device.ancMode == mode ? Color.blue : Color.clear)
                        .cornerRadius(8)
                    }
                }
            }
            
            // Volume Control
            GroupBox("Volume") {
                VStack {
                    HStack {
                        Image(systemName: "speaker.fill")
                        Slider(value: $volume, in: 0...1) { _ in
                            fastPairService.updateVolume(volume)
                        }
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    
                    Text("\(Int(volume * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // EQ Controls
            GroupBox("Equalizer") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    ForEach(EQPreset.allCases, id: \.self) { preset in
                        Button(action: {
                            selectedEQPreset = preset
                            fastPairService.setEQPreset(preset)
                        }) {
                            VStack {
                                Image(systemName: preset.icon)
                                    .font(.title3)
                                Text(preset.rawValue)
                                    .font(.caption)
                            }
                            .foregroundColor(selectedEQPreset == preset ? .white : .primary)
                        }
                        .buttonStyle(.bordered)
                        .background(selectedEQPreset == preset ? Color.blue : Color.clear)
                        .cornerRadius(6)
                    }
                }
            }
            
            // Battery Status
            if let battery = device.batteryLevel {
                GroupBox("Battery") {
                    HStack {
                        Image(systemName: battery > 20 ? "battery.100" : "battery.25")
                            .foregroundColor(battery > 20 ? .green : .red)
                        Text("\(battery)%")
                            .font(.headline)
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
    }
    
    private var scanButton: some View {
        Button(action: {
            if fastPairService.isScanning {
                fastPairService.stopScanning()
            } else {
                fastPairService.startScanning()
            }
        }) {
            HStack {
                Image(systemName: fastPairService.isScanning ? "stop.circle" : "magnifyingglass")
                Text(fastPairService.isScanning ? "Stop" : "Scan")
            }
        }
        .disabled(!fastPairService.isBluetoothReady)
    }
}

// MARK: - Menu Bar Support
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "BuzzPair")
            button.action = #selector(showPopover)
            button.target = self
        }
        
        // Configure popover
        popover.contentViewController = NSHostingController(rootView: ContentView())
        popover.behavior = .transient
    }
    
    @objc func showPopover() {
        if let button = statusItem?.button {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}

// MARK: - App Entry Point
@main
struct BuzzPairApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
