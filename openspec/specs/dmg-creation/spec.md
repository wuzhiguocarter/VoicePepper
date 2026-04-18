## Purpose

使用 create-dmg 工具为三种架构分别生成带拖拽安装体验的 DMG 安装镜像。

## Requirements

### Requirement: 三种架构 DMG 安装镜像生成
系统 SHALL 使用 `create-dmg` 工具为每种架构生成独立的 DMG 安装镜像。

#### Scenario: 生成 arm64 DMG
- **WHEN** arm64 .app bundle 已组装且签名完成
- **THEN** 系统生成 `VoicePepper-<version>-arm64.dmg` 文件

#### Scenario: 生成 x86_64 DMG
- **WHEN** x86_64 .app bundle 已组装且签名完成
- **THEN** 系统生成 `VoicePepper-<version>-x86_64.dmg` 文件

#### Scenario: 生成 Universal DMG
- **WHEN** Universal .app bundle 已组装且签名完成
- **THEN** 系统生成 `VoicePepper-<version>-universal.dmg` 文件

#### Scenario: DMG 文件名包含版本号和架构
- **WHEN** tag 为 `v1.2.3` 时生成 DMG
- **THEN** 生成 3 个文件：`VoicePepper-1.2.3-arm64.dmg`、`VoicePepper-1.2.3-x86_64.dmg`、`VoicePepper-1.2.3-universal.dmg`

### Requirement: 拖拽安装体验
DMG 打开后 SHALL 展示拖拽安装界面，包含应用图标和 Applications 文件夹快捷方式。

#### Scenario: DMG 内容布局
- **WHEN** 用户挂载 DMG
- **THEN** Finder 窗口显示 `VoicePepper.app` 和 `Applications` 文件夹快捷方式

#### Scenario: 拖拽安装
- **WHEN** 用户将 `VoicePepper.app` 拖拽到 `Applications` 快捷方式上
- **THEN** 应用被复制到 `/Applications/VoicePepper.app`

### Requirement: DMG 窗口尺寸和外观
DMG 打开后 SHALL 使用合理的窗口尺寸。

#### Scenario: 窗口配置
- **WHEN** DMG 被挂载并打开
- **THEN** Finder 窗口尺寸为 660x400 像素，图标大小为 160 像素

### Requirement: DMG 签名
生成的每个 DMG 文件 SHALL 被代码签名。

#### Scenario: DMG 代码签名
- **WHEN** 3 个 DMG 文件生成后
- **THEN** 系统使用 Developer ID 证书对每个 DMG 分别执行 `codesign`
