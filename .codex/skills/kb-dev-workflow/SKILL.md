---
name: kb-dev-workflow
description: >
  VoicePepper 仓库的端到端开发工作流编排器。适用于用户提出新功能、优化、重构或修复需求时，
  自动按顺序完成 OpenSpec 规格产出、代码实现、项目内验证、变更归档，以及提交并创建或更新 PR。
  触发示例：开发/实现/新增/修复/优化/重构某功能，或直接给出 PRD、需求说明、Bug 描述。
---

# KB Dev Workflow

这个 skill 用于 **VoicePepper 仓库内的完整研发闭环**。默认连续推进，不在中途为了形式化确认而停下；只有在需求存在关键歧义、会导致错误实现时，才向用户提出一个简短问题。

## 总原则

1. 先用 OpenSpec 产出或补齐变更文档，再开始代码实现。
2. 实现后必须做仓库内可执行的验证，优先运行真实构建和现有 E2E 测试。
3. 如果验证失败，先修复，再重跑验证；不要带着已知失败进入归档或提 PR。
4. 完成后归档 OpenSpec change，并把代码变化通过 commit/push/PR 发出去。
5. 全程给用户简短进度播报，例如：`步骤 2/5：实现代码`。

## 工作流

### 步骤 1：生成或更新 OpenSpec 变更

优先使用 `openspec-propose` skill，为当前需求创建完整 change 工件。

- 如果用户已经明确给出一个现成的 change 名称，沿用该 change。
- 如果仓库里已经有与当前需求明显对应的未归档 change，可以继续使用，不要重复创建。
- 目标是拿到可实施的 artifacts，至少包括：
  - `proposal.md`
  - `design.md`
  - `tasks.md`
  - 相关 `specs/*/spec.md`

完成后记录：

- change 名称
- change 路径
- `tasks.md` 路径

### 步骤 2：实现代码

使用 `openspec-apply-change` skill，围绕当前 change 持续推进，直到：

- 所有任务完成，或
- 出现必须由用户决策的真实阻塞

要求：

- 修改应保持聚焦，围绕当前 change 的任务落地。
- 每完成一项任务，立即把 `tasks.md` 中对应 checkbox 改为 `- [x]`。
- 记录本次变更涉及的文件路径，供后续测试选择使用。

### 步骤 3：项目内验证

VoicePepper 是 macOS 原生状态栏应用。默认验证顺序如下。

#### 3.1 锁定项目路径与证据目录

先执行：

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
BRANCH_NAME=$(git branch --show-current | sed 's/[^a-zA-Z0-9_-]/-/g')
DATE_PREFIX=$(date +%y%m%d%H)
SCREENSHOT_PREFIX="${BRANCH_NAME}_${DATE_PREFIX}"
TEST_RESULTS="$PROJECT_ROOT/test-results"
mkdir -p "$TEST_RESULTS"
```

后续所有截图和测试证据都放在 `$TEST_RESULTS` 下。

#### 3.2 构建并启动最新调试版本

```bash
cd "$PROJECT_ROOT"
swift build
pkill -9 -f ".build/debug/VoicePepper" 2>/dev/null || true
sleep 1
nohup "$PROJECT_ROOT/.build/debug/VoicePepper" > /tmp/voicepepper.log 2>&1 &
sleep 2
pgrep -f ".build/debug/VoicePepper"
```

如果 `swift build` 失败，回到步骤 2 修复，再重试本步骤。

启动后截图：

```bash
screencapture -x "$TEST_RESULTS/${SCREENSHOT_PREFIX}_01-app-launched.png"
```

#### 3.3 选择并运行 E2E 测试

根据改动文件选择测试：

- 触及一般 UI / App 流程：运行 `tests/e2e_test.py`
- 触及录音、音频采集、AVFoundation：额外运行 `tests/recording_e2e_test.py`
- 触及 `Sources/CWhisper/`、Whisper、转录链路：额外运行 `tests/transcription_e2e_test.py`
- 不确定或改动面较大：三个都跑

Python 解释器约定：

```bash
AX_PYTHON="arch -x86_64 /Users/wuzhiguo/projects/macos-ui-automation-mcp/.venv/bin/python3"
TRANS_PYTHON="python3"
```

执行示例：

```bash
cd "$PROJECT_ROOT"
$AX_PYTHON tests/e2e_test.py
screencapture -x "$TEST_RESULTS/${SCREENSHOT_PREFIX}_02-ui-test.png"

$AX_PYTHON tests/recording_e2e_test.py
screencapture -x "$TEST_RESULTS/${SCREENSHOT_PREFIX}_03-recording-test.png"

$TRANS_PYTHON tests/transcription_e2e_test.py
screencapture -x "$TEST_RESULTS/${SCREENSHOT_PREFIX}_04-transcription-test.png"
```

#### 3.4 结束态验证

测试结束后：

```bash
pgrep -f ".build/debug/VoicePepper"
screencapture -x "$TEST_RESULTS/${SCREENSHOT_PREFIX}_05-final-state.png"
ls "$TEST_RESULTS"/${SCREENSHOT_PREFIX}_*.png 2>/dev/null
```

判定规则：

- 关键构建和对应测试通过，才能进入下一步。
- 如果某次验证出现失败，但后续已修复并重测通过，记住本轮发生过“失败 -> 修复 -> 重测”。

#### 3.5 条件步骤：沉淀经验

只有在步骤 3 中发生过测试失败并修复后，才执行 `ce:compound` skill，把这次问题、根因、修复和验证过程沉淀到 `docs/solutions/`。

如果验证一次通过，跳过此步骤。

### 步骤 4：归档 OpenSpec change

使用 `openspec-archive-change` skill 归档当前 change。

要求：

- 如果存在 delta specs，优先同步后再归档。
- 如果 tasks 还有未完成项，先检查是否真的是漏项；能补就补，不要把明显未完成的实现直接归档。

### 步骤 5：提交、推送并创建或更新 PR

先检查当前分支是否已经存在 open PR：

```bash
gh pr list --head "$(git branch --show-current)" --state open --json number,title,url
```

分两种情况处理：

- 若已有 open PR：完成本次 commit 并 push，让改动同步到现有 PR。
- 若没有 open PR：使用 `git-commit-push-pr` skill 完成 commit、push、PR 创建。

如果步骤 3 生成了截图，优先把它们纳入 PR 描述。可按以下方式处理：

1. 使用临时 tag / release 上传截图资源。
2. 用 `gh pr edit --body-file ...` 更新 PR 描述。
3. 在 PR 描述中放入测试结论和截图链接，而不是原始命令输出。

常用命令：

```bash
git tag temp-screenshots
git push origin temp-screenshots
gh release create temp-screenshots --title "Test Screenshots (temp)" --notes "Temporary release for PR screenshots"
gh release upload temp-screenshots "$TEST_RESULTS"/${SCREENSHOT_PREFIX}_*.png --clobber
```

PR 描述至少应包含：

- 为什么做这次改动
- 主要用户可见变化
- 验证方式
- 如有截图，附截图链接

## 失败处理

- 构建失败：修复后重试构建。
- 测试失败：修复后重跑受影响测试，直到关键路径通过。
- `gh`、网络、推送或 release 操作被权限/沙箱拦住：按 Codex 当前环境请求授权后继续，不要静默跳过。
- 若当前分支已有用户未说明的额外脏改动，避免覆盖；只处理与当前需求直接相关的内容。

## 不要做的事

- 不要沿用不存在的旧 skill 名称，例如 `opsx:*`。
- 不要依赖当前环境里不存在的 MCP 工具作为主路径。
- 不要在验证失败时直接进入 archive 或 PR。
- 不要为了“问一下用户是否继续”而打断主流程。

## 完成标准

只有满足以下条件，才算完整执行完本 skill：

1. OpenSpec change 已创建并实现完毕。
2. 仓库内构建与对应测试已通过，或失败后已修复并重测通过。
3. 必要时经验已沉淀到 `docs/solutions/`。
4. change 已归档。
5. 代码已 commit、push，并创建或更新了 PR。
