## Purpose

macOS 代码签名和 Apple 公证配置，支持 CI 环境下的自动签名，以及无签名回退模式。

## Requirements

### Requirement: CI 环境证书管理
系统 SHALL 在 CI 环境中通过 GitHub Secrets 管理 Apple 签名证书。

#### Scenario: 临时 Keychain 创建
- **WHEN** CI 构建任务启动
- **THEN** 创建临时 Keychain，从 GitHub Secrets 导入 Developer ID 证书（.p12）

#### Scenario: 构建后清理 Keychain
- **WHEN** CI 构建任务结束（成功或失败）
- **THEN** 删除临时 Keychain，确保证书不残留

### Requirement: 应用代码签名
系统 SHALL 使用 Developer ID Application 证书对 .app bundle 进行深度签名。

#### Scenario: 深度签名
- **WHEN** .app bundle 组装完成
- **THEN** 执行 `codesign --deep --force --options runtime --sign "Developer ID Application: <TEAM>" --entitlements VoicePepper.entitlements VoicePepper.app`

#### Scenario: Frameworks 单独签名
- **WHEN** 对 .app 执行签名前
- **THEN** 先对 `Contents/Frameworks/` 下的每个 dylib 单独执行 `codesign --force --sign "Developer ID Application: <TEAM>"`

#### Scenario: 签名验证
- **WHEN** 签名完成后
- **THEN** `codesign -v --verbose=4 VoicePepper.app` 验证通过，无错误

### Requirement: Apple 公证提交
系统 SHALL 使用 `xcrun notarytool` 将签名后的 DMG 提交 Apple 公证。

#### Scenario: 公证提交
- **WHEN** DMG 文件已签名
- **THEN** 执行 `xcrun notarytool submit VoicePepper.dmg --apple-id <ID> --team-id <TEAM> --password <APP_PASSWORD> --wait`

#### Scenario: 公证成功后 staple
- **WHEN** Apple 公证审核通过
- **THEN** 执行 `xcrun stapler staple VoicePepper.dmg` 将公证票据附加到 DMG

#### Scenario: 公证失败处理
- **WHEN** Apple 公证审核失败
- **THEN** CI 任务失败并输出公证日志 URL 供开发者排查

### Requirement: 无签名回退模式
系统 SHALL 支持在未配置签名证书时跳过签名和公证步骤，生成未签名的 DMG。

#### Scenario: 无证书时跳过签名
- **WHEN** GitHub Secrets 中未配置 `APPLE_CERTIFICATE_BASE64`
- **THEN** 跳过代码签名和公证步骤，生成未签名的 DMG 并在日志中输出警告

#### Scenario: 未签名 DMG 可安装
- **WHEN** 用户下载未签名的 DMG
- **THEN** 用户可通过右键 → 打开 绕过 Gatekeeper 安装应用

### Requirement: GitHub Secrets 配置
系统 SHALL 使用以下 GitHub Secrets 存储签名凭据。

#### Scenario: 必需的 Secrets
- **WHEN** 配置签名功能时
- **THEN** 需要以下 GitHub Secrets：
  - `APPLE_CERTIFICATE_BASE64` — Developer ID 证书的 base64 编码
  - `APPLE_CERTIFICATE_PASSWORD` — 证书密码
  - `APPLE_ID` — Apple Developer 账号邮箱
  - `APPLE_TEAM_ID` — Apple Developer Team ID
  - `APPLE_APP_PASSWORD` — App-Specific Password（用于公证）
