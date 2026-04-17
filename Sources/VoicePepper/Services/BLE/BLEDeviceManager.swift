import Foundation
import CoreBluetooth
import Combine

// MARK: - Discovered Device

struct BLEDiscoveredDevice: Identifiable, Equatable {
    let id: UUID              // CBPeripheral.identifier
    let name: String
    var rssi: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - BLE Device Manager

/// 设备管理层：封装 CBCentralManager，负责扫描、连接、断开、重连及 Characteristic 交互
final class BLEDeviceManager: NSObject, ObservableObject {

    // MARK: Published State (SwiftUI @ObservedObject 驱动 PreferencesView)

    @Published private(set) var discoveredDevices: [BLEDiscoveredDevice] = []
    @Published private(set) var bluetoothPoweredOn: Bool = false

    /// 连接状态：手动 objectWillChange + 回调，替代 @Published（NSObject 子类的 @Published Combine 订阅不可靠）
    private(set) var connectionState: BLEConnectionState = .disconnected {
        didSet {
            NSLog("[BLEDeviceManager] connectionState: %@ → %@, callback=%@, self=%p",
                  String(describing: oldValue), String(describing: connectionState),
                  onConnectionStateChanged == nil ? "nil" : "set",
                  Unmanaged.passUnretained(self).toOpaque().debugDescription)
            objectWillChange.send()
            onConnectionStateChanged?(connectionState)
        }
    }

    var batteryLevel: Int? = nil {
        didSet {
            objectWillChange.send()
            onBatteryLevelChanged?(batteryLevel)
        }
    }

    var deviceStatus: BLEDeviceStatus = [] {
        didSet {
            objectWillChange.send()
            onDeviceStatusChanged?(deviceStatus)
        }
    }

    // MARK: Data Publishers

    /// 主数据通道（0xAE22）收到的原始数据
    let dataReceivedPublisher = PassthroughSubject<Data, Never>()
    /// 按键/电量通道（0xAE23）收到的原始数据
    let buttonReceivedPublisher = PassthroughSubject<Data, Never>()

    // MARK: State Change Callbacks

    /// 连接状态变化回调
    var onConnectionStateChanged: ((BLEConnectionState) -> Void)?
    var onBatteryLevelChanged: ((Int?) -> Void)?
    var onDeviceStatusChanged: ((BLEDeviceStatus) -> Void)?

    // MARK: Private

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var scanTimer: Timer?
    private var reconnectAttempt = 0
    private var reconnectTimer: Timer?
    private var lastConnectedDeviceID: UUID?

    /// 缓存已发现的 CBPeripheral 强引用，防止 ARC 回收导致连接失败
    private var peripheralCache: [UUID: CBPeripheral] = [:]

    private let bleProtocol = BLEProtocol()

    // MARK: Init

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: - Public API

    /// 开始扫描录音笔设备（10 秒超时）
    func startScan() {
        guard centralManager.state == .poweredOn else {
            NSLog("[BLEDeviceManager] 蓝牙未开启，无法扫描")
            return
        }
        discoveredDevices.removeAll()
        peripheralCache.removeAll()
        connectionState = .scanning

        centralManager.scanForPeripherals(
            withServices: [BLERecorderUUID.service],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        // 10 秒后自动停止扫描
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            self?.stopScan()
        }
        NSLog("[BLEDeviceManager] 开始扫描 BLE 录音笔设备")
    }

    /// 停止扫描
    func stopScan() {
        centralManager.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil
        if connectionState == .scanning {
            connectionState = .disconnected
        }
        NSLog("[BLEDeviceManager] 停止扫描")
    }

    /// 连接指定设备
    func connect(deviceID: UUID) {
        guard let peripheral = discoveredPeripheral(for: deviceID) else {
            NSLog("[BLEDeviceManager] 未找到设备 %@", deviceID.uuidString)
            return
        }
        stopScan()
        connectionState = .connecting
        lastConnectedDeviceID = deviceID
        reconnectAttempt = 0

        centralManager.connect(peripheral, options: nil)
        NSLog("[BLEDeviceManager] 连接设备: %@", peripheral.name ?? "Unknown")
    }

    /// 主动断开连接
    func disconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        reconnectAttempt = 0

        if let peripheral = connectedPeripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        cleanup()
        connectionState = .disconnected
        NSLog("[BLEDeviceManager] 主动断开连接")
    }

    /// 通过写入通道发送数据
    func sendData(_ data: Data) {
        guard let peripheral = connectedPeripheral,
              let characteristic = writeCharacteristic else {
            NSLog("[BLEDeviceManager] 无法发送：设备未连接或写入通道未就绪")
            return
        }
        NSLog("[BLEDeviceManager] 发送 %d 字节: %@", data.count, data.map { String(format: "%02X", $0) }.joined(separator: " "))
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }

    /// 发送封装好的协议包
    func sendCommand(type: BLEDataType, command: UInt8, payload: Data = Data()) {
        let packet = bleProtocol.pack(type: type, command: command, payload: payload)
        sendData(packet)
    }

    /// 发送 ACK 回复（使用接收包的 SeqNo）
    func sendACK(seqNo: UInt8, type: BLEDataType, command: UInt8, payload: Data = Data()) {
        let packet = bleProtocol.packACK(seqNo: seqNo, type: type, command: command, payload: payload)
        sendData(packet)
    }

    /// 查询设备电量
    func queryBattery() {
        sendCommand(type: .control, command: BLEControlCommand.getBattery.rawValue)
    }

    /// 查询设备状态
    func queryDeviceStatus() {
        sendCommand(type: .control, command: BLEControlCommand.getDeviceStatus.rawValue)
    }

    /// 同步时间到设备
    func syncTime() {
        let cal = Calendar.current
        let now = Date()
        let year = cal.component(.year, from: now)
        let month = cal.component(.month, from: now)
        let day = cal.component(.day, from: now)
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let second = cal.component(.second, from: now)

        var payload = Data()
        payload.append(UInt8(year & 0xFF))
        payload.append(UInt8((year >> 8) & 0xFF))
        payload.append(UInt8(month))
        payload.append(UInt8(day))
        payload.append(UInt8(hour))
        payload.append(UInt8(minute))
        payload.append(UInt8(second))

        sendCommand(type: .control, command: BLEControlCommand.syncTime.rawValue, payload: payload)
    }

    // MARK: - Private Helpers

    private func discoveredPeripheral(for deviceID: UUID) -> CBPeripheral? {
        // 优先从本地缓存获取（扫描时缓存的强引用）
        if let cached = peripheralCache[deviceID] { return cached }
        // 兜底：从系统已知设备列表获取（仅对之前配对/连接过的设备有效）
        return centralManager.retrievePeripherals(withIdentifiers: [deviceID]).first
    }

    private func cleanup() {
        connectedPeripheral = nil
        writeCharacteristic = nil
        batteryLevel = nil
        deviceStatus = []
    }

    // MARK: - Auto Reconnect

    private func attemptReconnect() {
        guard reconnectAttempt < BLEReconnectPolicy.maxAttempts,
              let deviceID = lastConnectedDeviceID else {
            connectionState = .disconnected
            NSLog("[BLEDeviceManager] 重连次数耗尽或无设备 ID，停止重连")
            return
        }

        reconnectAttempt += 1
        connectionState = .reconnecting(attempt: reconnectAttempt)
        let delay = BLEReconnectPolicy.delay(forAttempt: reconnectAttempt)
        NSLog("[BLEDeviceManager] 尝试重连 #%d，%0.0f 秒后执行", reconnectAttempt, delay)

        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self, let peripheral = self.discoveredPeripheral(for: deviceID) else {
                self?.attemptReconnect()
                return
            }
            self.centralManager.connect(peripheral, options: nil)
        }
    }

    /// 连接成功后的初始化流程
    private func onDeviceReady() {
        syncTime()
        queryBattery()
        queryDeviceStatus()
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEDeviceManager: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothPoweredOn = (central.state == .poweredOn)
        NSLog("[BLEDeviceManager] 蓝牙状态: %d", central.state.rawValue)

        if central.state != .poweredOn {
            connectionState = .disconnected
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "未知设备"
        let device = BLEDiscoveredDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue)

        // 缓存 CBPeripheral 强引用（关键！否则 ARC 回收后 connect 无响应）
        peripheralCache[peripheral.identifier] = peripheral

        if let idx = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[idx].rssi = device.rssi
        } else {
            discoveredDevices.append(device)
            NSLog("[BLEDeviceManager] 发现设备: %@ (RSSI: %d)", name, RSSI.intValue)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        NSLog("[BLEDeviceManager] 已连接: %@", peripheral.name ?? "Unknown")
        connectedPeripheral = peripheral
        peripheral.delegate = self
        reconnectAttempt = 0
        connectionState = .connected

        // 发现 Service
        peripheral.discoverServices([BLERecorderUUID.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        NSLog("[BLEDeviceManager] 连接失败: %@", error?.localizedDescription ?? "unknown")
        attemptReconnect()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        NSLog("[BLEDeviceManager] 设备断连: %@", error?.localizedDescription ?? "主动断开")
        cleanup()

        // 只在意外断连时自动重连（error != nil）
        if error != nil {
            attemptReconnect()
        } else {
            connectionState = .disconnected
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEDeviceManager: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services where service.uuid == BLERecorderUUID.service {
            peripheral.discoverCharacteristics([
                BLERecorderUUID.writeCharacteristic,
                BLERecorderUUID.dataNotifyCharacteristic,
                BLERecorderUUID.buttonNotifyCharacteristic
            ], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for char in characteristics {
            switch char.uuid {
            case BLERecorderUUID.writeCharacteristic:
                writeCharacteristic = char
                NSLog("[BLEDeviceManager] 写入通道就绪: 0xAE21")

            case BLERecorderUUID.dataNotifyCharacteristic:
                peripheral.setNotifyValue(true, for: char)
                NSLog("[BLEDeviceManager] 订阅数据通道: 0xAE22")

            case BLERecorderUUID.buttonNotifyCharacteristic:
                peripheral.setNotifyValue(true, for: char)
                NSLog("[BLEDeviceManager] 订阅按键/电量通道: 0xAE23")

            default:
                break
            }
        }

        // 所有 Characteristic 就绪后执行初始化
        if writeCharacteristic != nil {
            onDeviceReady()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            NSLog("[BLEDeviceManager] 接收错误 %@: %@", characteristic.uuid.uuidString, err.localizedDescription)
            return
        }
        guard let data = characteristic.value else { return }

        NSLog("[BLEDeviceManager] 接收 %@ %d 字节: %@",
              characteristic.uuid.uuidString, data.count,
              data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " "))

        switch characteristic.uuid {
        case BLERecorderUUID.dataNotifyCharacteristic:
            dataReceivedPublisher.send(data)

        case BLERecorderUUID.buttonNotifyCharacteristic:
            buttonReceivedPublisher.send(data)

        default:
            break
        }
    }
}
