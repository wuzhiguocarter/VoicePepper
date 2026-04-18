## ADDED Requirements

### Requirement: Tag 触发 Release 构建
系统 SHALL 在推送匹配 `v*` 模式的 Git tag 时自动触发 Release 构建流水线。

#### Scenario: 推送版本 tag 触发构建
- **WHEN** 开发者推送 tag `v1.0.0` 到 GitHub
- **THEN** GitHub Actions 自动启动 `build-release` workflow

#### Scenario: 非版本 tag 不触发
- **WHEN** 开发者推送 tag `test-123` 到 GitHub
- **THEN** `build-release` workflow 不被触发

### Requirement: PR 编译检查
系统 SHALL 在 Pull Request 创建或更新时执行编译检查（仅编译，不打包 DMG）。

#### Scenario: PR 编译通过
- **WHEN** 开发者创建或更新 Pull Request
- **THEN** CI 执行 `swift build` 编译检查并报告结果

#### Scenario: PR 编译失败阻止合并
- **WHEN** PR 的编译检查失败
- **THEN** GitHub 状态检查显示为失败，阻止自动合并

### Requirement: 双架构构建
系统 SHALL 在同一 CI 任务中分别为 arm64 和 x86_64 架构编译 Release 版本二进制。

#### Scenario: arm64 构建
- **WHEN** Release 构建流水线执行
- **THEN** 系统使用 `swift build -c release --arch arm64` 生成 arm64 二进制

#### Scenario: x86_64 构建
- **WHEN** Release 构建流水线执行
- **THEN** 系统使用 `arch -x86_64 swift build -c release --arch x86_64` 生成 x86_64 二进制

### Requirement: Universal Binary 合并
系统 SHALL 使用 `lipo` 将双架构二进制合并为 Universal Binary。

#### Scenario: lipo 合并成功
- **WHEN** arm64 和 x86_64 二进制均构建成功
- **THEN** 系统执行 `lipo -create -output VoicePepper arm64/VoicePepper x86_64/VoicePepper` 生成 Universal Binary

#### Scenario: 验证 Universal Binary
- **WHEN** Universal Binary 生成后
- **THEN** `lipo -info VoicePepper` 输出包含 `x86_64 arm64`

### Requirement: Homebrew 依赖缓存
系统 SHALL 缓存 Homebrew 安装的依赖库以加速后续构建。

#### Scenario: 首次构建安装并缓存依赖
- **WHEN** 缓存不存在时执行构建
- **THEN** 系统安装 whisper-cpp 和 opus，并将 Homebrew cellar 路径缓存

#### Scenario: 后续构建使用缓存
- **WHEN** 缓存命中时执行构建
- **THEN** 系统跳过 Homebrew 安装步骤，直接使用缓存的依赖

### Requirement: GitHub Release 自动发布
系统 SHALL 在构建和打包成功后自动创建 GitHub Release 并上传 DMG 文件。

#### Scenario: 自动创建 Release
- **WHEN** 所有 DMG 文件生成并签名/公证完成
- **THEN** 系统创建与 tag 同名的 GitHub Release，上传 3 个 DMG 作为附件：
  - `VoicePepper-<version>-arm64.dmg`（Apple Silicon）
  - `VoicePepper-<version>-x86_64.dmg`（Intel）
  - `VoicePepper-<version>-universal.dmg`（通用）

#### Scenario: Release 包含变更说明
- **WHEN** GitHub Release 创建时
- **THEN** Release body 自动包含自上一个 tag 以来的 commit 列表
