## MODIFIED Requirements

### Requirement: BLE 设备连接
系统 SHALL 在扫描发现设备时缓存 CBPeripheral 强引用，确保连接时对象不被 ARC 回收。PreferencesView SHALL 通过 EnvironmentObject 获取 AppDelegate 持有的唯一 BLEDeviceManager 实例。

#### Scenario: CBPeripheral 缓存
- **WHEN** CBCentralManager 发现一个 BLE 外围设备
- **THEN** 系统在 peripheralCache 字典中缓存该 CBPeripheral 的强引用，后续 connect 调用从缓存获取

#### Scenario: EnvironmentObject 实例共享
- **WHEN** 用户打开偏好设置窗口
- **THEN** AppDelegate 通过 .environmentObject(bleDeviceManager) 将唯一实例注入 PreferencesView，确保扫描/连接操作在 AppDelegate 持有的同一实例上执行

### Requirement: 设备信息查询
系统 SHALL 通过 didSet + 回调机制将连接状态、电量、设备状态同步到 AppState，供 Popover UI 显示。

#### Scenario: 状态回调同步
- **WHEN** BLEDeviceManager 的 connectionState 属性变化
- **THEN** didSet 触发 onConnectionStateChanged 回调，AppDelegate 在回调中直接赋值 appState.bleConnectionState，Popover 即时反映新状态
