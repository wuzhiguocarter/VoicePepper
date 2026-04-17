import CoreBluetooth

// MARK: - BLE Service / Characteristic UUIDs

enum BLERecorderUUID {
    /// 录音笔 BLE Service UUID (16-bit: 0xAE20)
    static let service = CBUUID(string: "AE20")
    /// App → 设备 写入通道 (WRITE_WITHOUT_RESPONSE)
    static let writeCharacteristic = CBUUID(string: "AE21")
    /// 设备 → App 主数据通道 (NOTIFY)
    static let dataNotifyCharacteristic = CBUUID(string: "AE22")
    /// 设备 → App 电量/按键通道 (NOTIFY)
    static let buttonNotifyCharacteristic = CBUUID(string: "AE23")
}

// MARK: - Packet Constants

enum BLEPacket {
    /// 数据包魔数
    static let magic: UInt8 = 0x5A
    /// 包头长度：Magic(1) + SeqNo(1) + CRC16(2) + DataLen(2)
    static let headerSize = 6
}

// MARK: - Data Type (数据包中第一字节)

enum BLEDataType: UInt8 {
    case control   = 0  // 控制命令
    case audio     = 1  // 音频数据 / 实时转写
    case file      = 2  // 文件传输
    case button    = 3  // 按键命令
}

// MARK: - Control Command (type=0, cmd)

enum BLEControlCommand: UInt8 {
    case syncTime          = 0   // App→Dev: 同步北京时间
    case getCapacity       = 1   // App→Dev: 获取容量
    case replyCapacity     = 2   // Dev→App: 回复容量
    case getBattery        = 3   // App→Dev: 获取电量
    case replyBattery      = 4   // Dev→App: 回复电量
    case getSettings       = 5   // App→Dev: 获取设备设置
    case getFirmware       = 10  // App→Dev: 获取固件版本
    case replyFirmware     = 11  // Dev→App: 回复固件版本
    case getSerial         = 12  // App→Dev: 获取序列号
    case replySerial       = 13  // Dev→App: 回复序列号
    case getDeviceStatus   = 14  // App→Dev: 获取设备状态
    case replyDeviceStatus = 15  // Dev→App: 回复设备状态
}

// MARK: - Realtime Transcription Command (type=1, cmd)

enum BLERealtimeCommand: UInt8 {
    case start       = 0  // App→Dev: 开始实时转写
    case audioData   = 1  // Dev→App: 实时音频数据
    case stop        = 2  // App→Dev: 结束实时转写
    case pauseResume = 3  // App→Dev: 暂停(1)/继续(0)转写
    case deviceState = 4  // Dev→App: 设备停止(2)/暂停(1)/继续(0)
}

// MARK: - Button Command (type=3, cmd)

enum BLEButtonCommand: UInt8 {
    // Dev→App (奇数)
    case devStartRecording  = 1  // 设备按键：开始录音
    case devSaveRecording   = 3  // 设备按键：保存录音
    case devPauseRecording  = 5  // 设备按键：暂停录音
    case devResumeRecording = 7  // 设备按键：继续录音

    // App→Dev (偶数，ACK 回复)
    case ackStartRecording  = 2  // App 回复：开始录音结果
    case ackSaveRecording   = 4  // App 回复：保存录音结果
    case ackPauseRecording  = 6  // App 回复：暂停录音结果
    case ackResumeRecording = 8  // App 回复：继续录音结果
}

// MARK: - Device Status Bitmask (type=0, cmd=15 回复)

struct BLEDeviceStatus: OptionSet {
    let rawValue: UInt8

    static let playing          = BLEDeviceStatus(rawValue: 1 << 0)
    static let recording        = BLEDeviceStatus(rawValue: 1 << 1)
    static let usbMode          = BLEDeviceStatus(rawValue: 1 << 2)
    static let realtimeTranscr  = BLEDeviceStatus(rawValue: 1 << 3)
    static let importing        = BLEDeviceStatus(rawValue: 1 << 4)
    static let playPaused       = BLEDeviceStatus(rawValue: 1 << 5)
    static let busy             = BLEDeviceStatus(rawValue: 1 << 6)

    /// 0 表示空闲
    var isIdle: Bool { rawValue == 0 }
}

// MARK: - BLE Connection State

enum BLEConnectionState: Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case reconnecting(attempt: Int)
}

// MARK: - Reconnect Policy

enum BLEReconnectPolicy {
    static let maxAttempts = 5
    /// 指数退避间隔（秒）：2, 4, 8, 16, 32
    static func delay(forAttempt attempt: Int) -> TimeInterval {
        pow(2.0, Double(min(attempt, maxAttempts)))
    }
}
