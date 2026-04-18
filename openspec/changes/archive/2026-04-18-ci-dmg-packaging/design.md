## Context

VoicePepper 是一个基于 SPM 构建的 macOS 状态栏应用，依赖 Homebrew 安装的 whisper-cpp 和 opus 系统库。当前构建产物是一个裸 executable（`.build/debug/VoicePepper`），不是标准 `.app` bundle，也没有 CI 流水线。

用户需要通过 DMG 安装镜像直接下载和安装，且需要同时支持 Intel (x86_64) 和 Apple Silicon (arm64) 架构。

关键约束：
- Package.swift 中 Homebrew 路径硬编码为 `/opt/homebrew`（arm64），Intel 路径为 `/usr/local`
- 依赖的 whisper-cpp 和 opus 是动态链接库，分发时必须嵌入 .app bundle
- 应用使用了 App Sandbox=false（全局快捷键需要），走 Developer ID 直接分发而非 Mac App Store
- macOS 13.0+ 最低部署目标

## Goals / Non-Goals

**Goals:**
- 通过 Git tag (v*) 自动触发 GitHub Actions 构建和发布
- 生成三种 DMG：arm64（Apple Silicon）、x86_64（Intel）、Universal Binary，用户按需下载
- arm64/x86_64 单架构 DMG 体积更小，适合明确知道自己芯片类型的用户
- 将所有动态库依赖嵌入 .app bundle，用户无需安装 Homebrew
- 使用 Developer ID 签名 + Apple 公证，macOS Gatekeeper 无警告
- DMG 提供拖拽安装体验（应用图标 + Applications 文件夹快捷方式）

**Non-Goals:**
- Mac App Store 分发（当前 Sandbox 禁用，不兼容 MAS 要求）
- 自动更新机制（Sparkle 等，后续迭代考虑）
- Windows/Linux 跨平台构建
- 每次 commit 触发完整构建（仅 tag 触发 release，PR 仅做编译检查）

## Decisions

### D1: 构建方式 — SPM + 手动 .app bundle 组装

**选择**: 使用 `swift build -c release` 构建，然后通过 shell 脚本手动组装 .app bundle 目录结构。

**备选方案**:
- Xcode `xcodebuild`：需要 .xcodeproj 文件，当前项目是纯 SPM，引入 .xcodeproj 会增加维护负担
- Xcode SPM workspace：`xcodebuild -workspace` 可以用 SPM，但仍需额外配置 scheme/archive

**理由**: 项目已深度使用 SPM，.app bundle 结构简单（Info.plist + executable + Frameworks/），脚本组装更透明可控。

### D2: Universal Binary 策略 — 双架构独立编译 + lipo 合并

**选择**: 分别为 arm64 和 x86_64 编译，使用 `lipo -create` 合并为 Universal Binary。Homebrew 依赖同样为两个架构分别安装和嵌入。

**备选方案**:
- 仅发布 Universal Binary：体积翻倍，部分用户不需要另一架构
- 仅发布单架构 DMG：不熟悉芯片的用户可能下载错误版本
- 交叉编译：SPM 不原生支持交叉编译，复杂度高

**理由**: 三种 DMG 同时发布兼顾所有场景 — Universal 版适合不确定芯片的用户，单架构版体积更小。`lipo` 是 Apple 官方推荐的 Universal Binary 创建方式。构建脚本先独立编译两个架构的 .app bundle，再用 `lipo` 合并出第三个 Universal 版本，三个 .app 各自打包为 DMG。

### D3: 动态库嵌入策略 — @rpath + install_name_tool

**选择**: 将 libwhisper、libggml、libggml-base、libopus 的 dylib 复制到 `.app/Contents/Frameworks/`，使用 `install_name_tool -change` 将 rpath 从 Homebrew 绝对路径改写为 `@executable_path/../Frameworks/`。

**理由**: macOS 标准做法，确保 .app 自包含所有依赖，用户无需安装任何前置软件。

### D4: CI 平台 — GitHub Actions macOS runner

**选择**: 使用 `macos-15` runner（Apple Silicon），Intel 构建通过 `arch -x86_64` 前缀执行。

**备选方案**:
- Self-hosted runner：需要维护基础设施
- 双 runner 矩阵（macos-13 for Intel + macos-15 for ARM）：成本翻倍，且最终仍需 lipo 合并

**理由**: GitHub 提供的 macos-15 runner 是 M1 芯片，通过 Rosetta 2 可以执行 x86_64 构建，单 runner 即可完成双架构构建。

### D5: 签名和公证 — CI 环境 Keychain + xcrun notarytool

**选择**: 将 Developer ID 证书（.p12）和密码存为 GitHub Secrets，CI 中创建临时 Keychain 导入证书，使用 `codesign` 签名后通过 `xcrun notarytool` 提交公证。

**理由**: Apple 标准公证流程，`notarytool` 是 `altool` 的替代品（Apple 推荐）。

### D6: DMG 创建 — create-dmg 工具

**选择**: 使用 `create-dmg` (Homebrew 安装) 生成带自定义背景和 Applications 快捷方式的 DMG。

**备选方案**:
- `hdiutil`：原生但需要大量参数配置，无法方便地设置背景图和图标位置
- `dmgbuild` (Python)：功能强大但增加 Python 依赖

**理由**: `create-dmg` 是社区标准工具，一条命令即可生成专业品质的 DMG。

## Risks / Trade-offs

- **[风险] x86_64 Homebrew 依赖安装慢** → GitHub Actions macOS runner 上 x86_64 Homebrew 需要从源码编译部分依赖。缓解：使用 actions/cache 缓存 Homebrew 安装结果。

- **[风险] whisper-cpp x86_64 编译可能失败** → whisper.cpp 的某些优化依赖 ARM NEON 指令。缓解：CI 中使用 `WHISPER_NO_ACCELERATE=1` 或检查 x86_64 编译标志兼容性。

- **[风险] 签名证书过期** → Developer ID 证书有效期通常为 5 年。缓解：设置 GitHub Actions secret 过期提醒。

- **[权衡] 三种 DMG 增加构建时间和 Release 附件数量** → 构建时间增加不多（.app 组装和 DMG 创建很快，主要耗时在编译），Release 页面 3 个下载链接清晰明了。

- **[权衡] 无 Apple Developer 账号时无法签名/公证** → 首次配置需要付费 Apple Developer Program（$99/年）。缓解：脚本支持无签名模式（开发/测试用），签名配置为可选步骤。

## Open Questions

1. 是否已有 Apple Developer ID 证书？如果没有，首个版本是否可以先发布未签名版本（用户需要手动信任）？
2. 应用图标（.icns）是否已准备好？DMG 背景图是否需要设计？
3. 是否需要在 PR 阶段也执行编译检查（不打包，仅验证编译通过）？
