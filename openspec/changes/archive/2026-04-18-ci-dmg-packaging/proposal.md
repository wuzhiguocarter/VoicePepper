## Why

VoicePepper 目前没有自动化构建和分发流程。用户无法直接下载安装应用，开发者需要手动在本地构建并传递二进制文件。建立 CI 流水线自动打包 DMG 安装镜像，支持 Intel 和 Apple Silicon 双架构，让用户从 GitHub Releases 直接下载即可安装使用。

## What Changes

- 新增 GitHub Actions CI 流水线，自动构建 Release 版本二进制
- 新增构建脚本，将 SPM executable 打包为标准 `.app` bundle（含 Info.plist、Entitlements、图标、依赖 dylib）
- 支持三种架构打包：arm64（Apple Silicon）、x86_64（Intel）、Universal Binary（arm64 + x86_64），用户可按需下载
- 将 Homebrew 系统依赖（whisper-cpp、opus）的动态库打包进 `.app`，实现零依赖分发
- 使用 `create-dmg` 或 `hdiutil` 生成带背景图和 Applications 快捷方式的 DMG 安装镜像（每次发布生成 3 个 DMG：arm64、x86_64、universal）
- 配置代码签名（Developer ID）和公证（Notarization），确保 macOS Gatekeeper 放行
- 通过 Git tag 触发自动发布到 GitHub Releases

## Capabilities

### New Capabilities
- `ci-build-pipeline`: GitHub Actions 流水线配置，定义触发条件、构建矩阵、缓存策略和发布流程
- `app-bundle-packaging`: 将 SPM executable 组装为标准 macOS `.app` bundle，嵌入依赖 dylib 并修正 rpath
- `dmg-creation`: DMG 安装镜像生成，包含应用拖拽安装体验
- `code-signing-notarization`: 代码签名和 Apple 公证配置，支持 CI 环境下的自动签名

### Modified Capabilities

（无现有 spec 需要修改）

## Impact

- **新增文件**: `.github/workflows/build-release.yml`、`scripts/build-app.sh`、`scripts/create-dmg.sh`
- **依赖变更**: CI 环境需安装 Homebrew、whisper-cpp、opus；需要 `create-dmg` 工具
- **签名要求**: 需要 Apple Developer ID 证书和 App-Specific Password（存为 GitHub Secrets）
- **Package.swift**: 可能需要调整以支持 x86_64 架构的 Homebrew 路径（当前硬编码 `/opt/homebrew`，Intel 为 `/usr/local`）
- **分发方式**: GitHub Releases 作为主要分发渠道
