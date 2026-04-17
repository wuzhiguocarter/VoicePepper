import Foundation

// MARK: - Parsed Packet

/// 解析后的 BLE 数据包
struct BLEParsedPacket {
    let seqNo: UInt8
    let dataType: UInt8    // BLEDataType rawValue
    let command: UInt8     // 命令字节（数据内容的第二字节）
    let payload: Data      // 命令参数（去除 type + cmd 后的剩余部分）
}

// MARK: - BLE Protocol (数据包封装/解析)

/// 纯数据层：负责 BLE 通信协议的包封装与解析，无 CoreBluetooth 依赖
final class BLEProtocol {

    /// 当前发送包序号（0-255 循环）
    private var sendSeqNo: UInt8 = 0

    // MARK: - Pack (封装)

    /// 封装一个完整的 BLE 数据包
    /// - Parameters:
    ///   - type: 数据类型（控制命令/音频/文件/按键）
    ///   - command: 命令字节
    ///   - payload: 命令参数（可选）
    /// - Returns: 待发送的完整数据包
    func pack(type: BLEDataType, command: UInt8, payload: Data = Data()) -> Data {
        let seq = nextSeqNo()
        return packWithSeqNo(seq, type: type, command: command, payload: payload)
    }

    /// 封装 ACK 回复包（使用接收包的 SeqNo）
    func packACK(seqNo: UInt8, type: BLEDataType, command: UInt8, payload: Data = Data()) -> Data {
        return packWithSeqNo(seqNo, type: type, command: command, payload: payload)
    }

    // MARK: - Unpack (解析)

    /// 解析接收到的 BLE 数据包
    /// - Parameter data: 原始字节数据
    /// - Returns: 解析后的数据包，校验失败返回 nil
    func unpack(_ data: Data) -> BLEParsedPacket? {
        guard data.count >= BLEPacket.headerSize + 1 else {
            NSLog("[BLEProtocol] 数据包过短: %d bytes", data.count)
            return nil
        }

        // Magic 校验
        guard data[0] == BLEPacket.magic else {
            NSLog("[BLEProtocol] Magic 校验失败: 0x%02X", data[0])
            return nil
        }

        let seqNo = data[1]
        let receivedCRC = UInt16(data[2]) | (UInt16(data[3]) << 8) // 小端序
        let dataLen = UInt16(data[4]) | (UInt16(data[5]) << 8)     // 小端序

        // 长度校验
        let expectedTotal = BLEPacket.headerSize + Int(dataLen)
        guard data.count >= expectedTotal else {
            NSLog("[BLEProtocol] 数据不完整: 需要 %d, 实际 %d", expectedTotal, data.count)
            return nil
        }

        // CRC 校验：计算范围 = DataLen(2B) + Data(nB)
        let crcRegion = data[4..<(BLEPacket.headerSize + Int(dataLen))]
        let computedCRC = Self.crc16XMODEM(Data(crcRegion))
        guard receivedCRC == computedCRC else {
            NSLog("[BLEProtocol] CRC 校验失败: 接收 0x%04X, 计算 0x%04X", receivedCRC, computedCRC)
            return nil
        }

        // 提取数据内容
        let contentStart = BLEPacket.headerSize
        let contentEnd = contentStart + Int(dataLen)
        let content = data[contentStart..<contentEnd]

        guard content.count >= 1 else { return nil }

        let dataType = content[contentStart]
        let command: UInt8 = content.count >= 2 ? content[contentStart + 1] : 0
        let payload: Data = content.count > 2
            ? Data(content[(contentStart + 2)...])
            : Data()

        return BLEParsedPacket(
            seqNo: seqNo,
            dataType: dataType,
            command: command,
            payload: payload
        )
    }

    // MARK: - CRC-16/XMODEM

    /// CRC-16/XMODEM 计算（多项式 0x1021，初始值 0x0000）
    static func crc16XMODEM(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0x0000
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 {
                if crc & 0x8000 != 0 {
                    crc = (crc << 1) ^ 0x1021
                } else {
                    crc <<= 1
                }
            }
        }
        return crc
    }

    // MARK: - Private

    private func nextSeqNo() -> UInt8 {
        let seq = sendSeqNo
        sendSeqNo = sendSeqNo &+ 1  // 溢出自动回到 0
        return seq
    }

    private func packWithSeqNo(_ seqNo: UInt8, type: BLEDataType, command: UInt8, payload: Data) -> Data {
        // Data 区域：type(1B) + command(1B) + payload(nB)
        var content = Data([type.rawValue, command])
        content.append(payload)

        let dataLen = UInt16(content.count)

        // CRC 计算范围：DataLen(2B) + Data(nB)
        var crcInput = Data()
        crcInput.append(UInt8(dataLen & 0xFF))        // DataLen 低字节
        crcInput.append(UInt8((dataLen >> 8) & 0xFF))  // DataLen 高字节
        crcInput.append(content)
        let crc = Self.crc16XMODEM(crcInput)

        // 组装完整数据包
        var packet = Data()
        packet.append(BLEPacket.magic)
        packet.append(seqNo)
        packet.append(UInt8(crc & 0xFF))               // CRC 低字节
        packet.append(UInt8((crc >> 8) & 0xFF))         // CRC 高字节
        packet.append(UInt8(dataLen & 0xFF))            // DataLen 低字节
        packet.append(UInt8((dataLen >> 8) & 0xFF))      // DataLen 高字节
        packet.append(content)

        return packet
    }
}
