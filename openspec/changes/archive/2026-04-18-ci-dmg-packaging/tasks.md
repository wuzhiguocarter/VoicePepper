## 1. 构建脚本 — .app Bundle 组装

- [x] 1.1 创建 `scripts/build-app.sh`，接受 `--arch` 参数（arm64 / x86_64 / universal），实现 `swift build -c release` 编译
- [x] 1.2 添加 x86_64 编译支持（`arch -x86_64 swift build`），处理 Homebrew 路径差异（`/opt/homebrew` vs `/usr/local`）
- [x] 1.3 实现 `lipo -create` 合并双架构二进制为 Universal Binary（仅 `--arch universal` 时执行）
- [x] 1.4 组装 .app bundle 目录结构（`Contents/MacOS/`、`Contents/Resources/`、`Contents/Frameworks/`、`Contents/Info.plist`）
- [x] 1.5 嵌入依赖 dylib（libwhisper、libggml、libggml-base、libopus）到 `Contents/Frameworks/`，按目标架构选择对应 dylib
- [x] 1.6 使用 `install_name_tool -change` 修正所有 dylib 的 rpath 为 `@executable_path/../Frameworks/`
- [x] 1.7 Universal 模式下为嵌入的 dylib 也执行 `lipo -create` 合并为 Universal 版本
- [x] 1.8 本地验证：在未安装 Homebrew 依赖的环境下验证各架构 .app 可正常启动

## 2. DMG 安装镜像生成

- [x] 2.1 创建 `scripts/create-dmg.sh`，接受 `--arch` 参数，使用 `create-dmg` 工具生成 DMG
- [x] 2.2 配置 DMG 窗口尺寸（660x400）、图标大小（160px）和 Applications 快捷方式
- [x] 2.3 实现版本号从 Git tag 提取并写入 DMG 文件名：`VoicePepper-<version>-<arch>.dmg`（arm64 / x86_64 / universal）
- [x] 2.4 本地验证：挂载各架构 DMG 检查拖拽安装体验

## 3. 代码签名与公证

- [x] 3.1 在 `scripts/build-app.sh` 中添加代码签名逻辑：先签 Frameworks 下每个 dylib，再深度签名 .app bundle（附带 entitlements）
- [x] 3.2 添加 DMG 签名步骤（对 3 个 DMG 分别签名）
- [x] 3.3 实现 `xcrun notarytool submit --wait` 公证提交和 `xcrun stapler staple` 票据附加（对 3 个 DMG 分别公证）
- [x] 3.4 实现无签名回退模式：检测 Secrets 是否配置，未配置时跳过签名/公证并输出警告
- [x] 3.5 添加 `codesign -v --verbose=4` 签名验证步骤

## 4. GitHub Actions 流水线

- [x] 4.1 创建 `.github/workflows/build-release.yml`，配置 `v*` tag push 触发 Release 构建
- [x] 4.2 添加 PR 编译检查 job（仅 `swift build`，不打包）
- [x] 4.3 配置 Homebrew 依赖安装步骤（whisper-cpp、opus、create-dmg），双架构分别安装
- [x] 4.4 添加 `actions/cache` 缓存 Homebrew 安装结果
- [x] 4.5 集成构建脚本，分别调用 `build-app.sh --arch arm64`、`build-app.sh --arch x86_64`、`build-app.sh --arch universal`
- [x] 4.6 集成 DMG 生成脚本，分别调用 `create-dmg.sh --arch arm64`、`create-dmg.sh --arch x86_64`、`create-dmg.sh --arch universal`
- [x] 4.7 配置临时 Keychain 创建和证书导入（从 GitHub Secrets）
- [x] 4.8 添加构建后 Keychain 清理步骤（always 执行）
- [x] 4.9 配置 GitHub Release 创建，上传 3 个 DMG（使用 `softprops/action-gh-release`）
- [x] 4.10 配置 Release body 自动生成 changelog（自上一个 tag 以来的 commits）

## 5. Package.swift 适配

- [x] 5.1 修改 Package.swift 支持动态 Homebrew 路径检测（arm64: `/opt/homebrew`，x86_64: `/usr/local`）
- [ ] 5.2 验证 x86_64 架构下 SPM 编译通过

## 6. 文档与验证

- [x] 6.1 在 SETUP.md 中添加 CI 配置说明（GitHub Secrets 设置指引）
- [ ] 6.2 端到端验证：模拟 tag push，确认完整流水线从编译到 Release 发布正常工作（3 个 DMG 均上传成功）
