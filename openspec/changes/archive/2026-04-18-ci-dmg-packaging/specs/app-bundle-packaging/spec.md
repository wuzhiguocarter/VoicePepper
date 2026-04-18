## ADDED Requirements

### Requirement: .app bundle 目录结构
系统 SHALL 将 SPM executable 组装为标准 macOS `.app` bundle，目录结构符合 Apple 规范。

#### Scenario: 标准 bundle 结构
- **WHEN** 构建脚本执行 .app 组装
- **THEN** 生成的 `VoicePepper.app` 包含以下结构：
  - `Contents/MacOS/VoicePepper` — 主可执行文件
  - `Contents/Info.plist` — 应用元数据
  - `Contents/Resources/` — 资源文件目录
  - `Contents/Frameworks/` — 嵌入的动态库

### Requirement: Info.plist 嵌入
系统 SHALL 将项目中的 `Resources/Info.plist` 复制到 `.app/Contents/Info.plist`。

#### Scenario: Info.plist 正确嵌入
- **WHEN** .app bundle 组装完成
- **THEN** `Contents/Info.plist` 中 `CFBundleIdentifier` 为 `com.voicepepper.app`，`LSUIElement` 为 `true`

### Requirement: 动态库嵌入与 rpath 修正
系统 SHALL 将 whisper-cpp 和 opus 的动态库复制到 `.app/Contents/Frameworks/` 并修正 rpath。

#### Scenario: dylib 嵌入
- **WHEN** 构建脚本执行动态库嵌入
- **THEN** 以下 dylib 被复制到 `Contents/Frameworks/`：
  - `libwhisper.dylib`
  - `libggml.dylib`
  - `libggml-base.dylib`
  - `libopus.dylib`（及其版本符号链接）

#### Scenario: rpath 修正
- **WHEN** dylib 嵌入完成
- **THEN** 主可执行文件和所有 dylib 的加载路径通过 `install_name_tool -change` 从 Homebrew 绝对路径改写为 `@executable_path/../Frameworks/`

#### Scenario: 独立运行验证
- **WHEN** 在未安装 Homebrew 依赖的 Mac 上运行 `VoicePepper.app`
- **THEN** 应用正常启动，不报 dylib 找不到的错误

### Requirement: 三种架构 .app bundle
系统 SHALL 分别组装 arm64、x86_64 和 Universal 三种 .app bundle。

#### Scenario: arm64 .app bundle
- **WHEN** arm64 编译完成
- **THEN** 组装仅包含 arm64 二进制和 arm64 dylib 的 `VoicePepper.app`

#### Scenario: x86_64 .app bundle
- **WHEN** x86_64 编译完成
- **THEN** 组装仅包含 x86_64 二进制和 x86_64 dylib 的 `VoicePepper.app`

#### Scenario: Universal .app bundle
- **WHEN** 双架构二进制均构建成功
- **THEN** 使用 `lipo -create` 合并二进制和 dylib 为 Universal 版本，组装 `VoicePepper.app`

### Requirement: Entitlements 签名应用
系统 SHALL 在代码签名时使用项目中的 `VoicePepper.entitlements` 文件。

#### Scenario: entitlements 应用
- **WHEN** 对 .app bundle 执行代码签名
- **THEN** 使用 `--entitlements Sources/VoicePepper/Resources/VoicePepper.entitlements` 参数
