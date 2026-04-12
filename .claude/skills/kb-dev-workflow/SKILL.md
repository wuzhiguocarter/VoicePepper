---
name: kb-dev-workflow
description: |
  全自动研发工作流编排器（VoicePepper macOS Native App 专用）。当用户描述任何开发需求时，自动连续执行完整五步流程：
  propose规格文档 → apply代码实现 → test-macos端到端测试 → archive归档 → commit-push-pr提交PR。

  触发条件（凡满足其一即触发）：
  - 用户描述一个新功能："开发X"、"实现Y"、"新增Z"、"做一个..."
  - 用户提出优化："优化..."、"改进..."、"重构..."
  - 用户报告 Bug："修复..."、"fix..."、"有个问题..."
  - 用户说"新需求："或给出 PRD/需求描述

  重要：用户描述需求后立即触发，不等待用户逐步调用每个子命令。如果无法确定是否为开发需求，默认触发。
---

# 全自动研发工作流（VoicePepper macOS Native App）

用户描述需求后，你的唯一任务是**不中断地顺序执行以下五个步骤**，直到 PR 创建完成。
每一步通过 Skill 工具调用对应子 Skill，上一步的产物作为下一步的上下文。

---

## 步骤 1：生成规格文档

**调用：** `Skill("opsx:propose", args="<需求描述>")`

将用户的原始需求描述作为 args 传入。opsx:propose 会自动创建 change 并生成全套规格文档（proposal.md + design.md + specs/*.md + tasks.md）。

**衔接：** propose 完成后，从输出或 `openspec/changes/` 目录中确认 change 名称（kebab-case），记录到上下文供后续步骤使用。

---

## 步骤 2：实现代码

**调用：** `Skill("opsx:apply")`

无需传额外参数，opsx:apply 会从当前 openspec 状态自动识别待实现的 change。
逐条完成 tasks.md 中的任务，每条完成后打 `[x]`，直到所有任务完成。

**衔接：** apply 完成后，记录本次改动涉及的文件路径（用于步骤 3 推断测试场景）。

---

## 步骤 3：macOS UI 端到端测试

> VoicePepper 是 macOS 状态栏 Native App，使用 AX（Accessibility API）自动化测试，不使用 agent-browser。

### 第一步：锁定项目根目录

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
BRANCH_NAME=$(git branch --show-current | sed 's/[^a-zA-Z0-9_-]/-/g')
DATE_PREFIX=$(date +%y%m%d%H)
SCREENSHOT_PREFIX="${BRANCH_NAME}_${DATE_PREFIX}"
TEST_RESULTS="$PROJECT_ROOT/test-results"
mkdir -p "$TEST_RESULTS"
echo "测试证据目录：$TEST_RESULTS"
echo "截图前缀：$SCREENSHOT_PREFIX"
```

将 `$PROJECT_ROOT`、`$TEST_RESULTS`、`$SCREENSHOT_PREFIX` 记录到上下文，后续所有截图命令都使用绝对路径。

### 第二步：构建并重启 App

```bash
cd "$PROJECT_ROOT"

# 编译 Debug 版本
swift build 2>&1 | tail -20

# 终止旧进程（若有）
pkill -9 -f ".build/debug/VoicePepper" 2>/dev/null
sleep 1

# 启动新进程
nohup "$PROJECT_ROOT/.build/debug/VoicePepper" > /tmp/voicepepper.log 2>&1 &
sleep 2  # 等待状态栏图标出现

echo "VoicePepper 启动完成，PID=$(pgrep -f '.build/debug/VoicePepper')"
```

**构建失败处理：** 若 `swift build` 报错，就地修复编译错误（调用 opsx:apply 继续修复），再重试构建，不跳过此步骤。

### 第三步：AX 可达性快速验证（macos-ui-automation MCP）

使用 macos-ui-automation MCP 工具做快速 sanity check，确认 App 已正常挂载到 AX 树：

1. 调用 `mcp__macos-ui-automation__list_running_applications` → 确认 VoicePepper 在运行
2. 调用 `mcp__macos-ui-automation__get_app_overview` (app_name="VoicePepper") → 查看 AX 结构概览
3. 调用 `mcp__macos-ui-automation__find_elements_in_app` (app_name="VoicePepper", role="AXButton") → 确认状态栏按钮可访问

> **重要 AX 规则（踩坑记录）：**
> - 状态栏图标在 `AXExtrasMenuBar` 属性下，不在常规 AXChildren 树里
> - Zombie 进程处理：用 AX 响应（AXExtrasMenuBar 非空）而非 max(PID) 判断活跃进程
> - 若 find_elements_in_app 返回空，等待 1-2s 后重试（App 刚启动时 AX 树可能还未就绪）

取初始截图：
```bash
screencapture -x "$TEST_RESULTS/${SCREENSHOT_PREFIX}_01-app-launched.png"
```

### 第四步：运行 Python E2E 测试脚本

根据步骤 2 产生的文件变更，按以下优先级选择要运行的测试：

| 改动文件包含 | 运行的测试 |
|---|---|
| `Sources/VoicePepper/` (UI/View 相关) | `tests/e2e_test.py` |
| `Sources/VoicePepper/` (Recording/Audio/AVFoundation) | `tests/e2e_test.py` + `tests/recording_e2e_test.py` |
| `Sources/CWhisper/` 或转录相关 | `tests/e2e_test.py` + `tests/transcription_e2e_test.py` |
| 全局改动 / 不确定 | 三个测试全部运行 |

**Python 环境说明（必须遵守）：**
```bash
# AX UI 测试：需要 PyObjC，必须用 x86_64 venv
AX_PYTHON="arch -x86_64 /Users/wuzhiguo/projects/macos-ui-automation-mcp/.venv/bin/python3"

# 转录测试：纯 Python，用系统 arm64 python3
TRANS_PYTHON="python3"
```

**运行示例：**
```bash
cd "$PROJECT_ROOT"

# 基础 UI 测试（几乎每次都要跑）
$AX_PYTHON tests/e2e_test.py
screencapture -x "$TEST_RESULTS/${SCREENSHOT_PREFIX}_02-ui-test.png"

# 录音测试（录音相关改动时）
$AX_PYTHON tests/recording_e2e_test.py
screencapture -x "$TEST_RESULTS/${SCREENSHOT_PREFIX}_03-recording-test.png"

# 转录测试（Whisper/CWhisper 相关改动时）
$TRANS_PYTHON tests/transcription_e2e_test.py
screencapture -x "$TEST_RESULTS/${SCREENSHOT_PREFIX}_04-transcription-test.png"
```

### 第五步：AX 状态后验证

测试完成后，用 macos-ui-automation 做终态检查：

1. 调用 `mcp__macos-ui-automation__find_elements_in_app` 确认 App 状态正常（无崩溃）
2. 若测试打开了 Popover，确认已正常关闭
3. 取最终截图：

```bash
screencapture -x "$TEST_RESULTS/${SCREENSHOT_PREFIX}_05-final-state.png"
```

**衔接：** test 完成后：
1. 记录测试通过/失败状态
2. 收集测试证据清单（供步骤 5 写入 PR body）：
   ```bash
   ls "$TEST_RESULTS"/${SCREENSHOT_PREFIX}_*.png 2>/dev/null
   ```
3. 若关键测试失败，先修复代码（调用 opsx:apply 继续修复），再重新测试，直到核心功能验证通过

**若本次测试出现过失败并修复（即经历了"发现问题 → 修复 → 重测通过"的循环），则在进入步骤 4 之前，执行步骤 3.5 记录经验教训。**

---

## 步骤 3.5（条件触发）：记录经验教训

**触发条件：** 步骤 3 中发生过测试失败并完成修复。若测试一次通过，跳过此步骤。

**调用：** `Skill("compound-engineering:ce:compound")`

此步骤将把刚才"发现 Bug → 定位根因 → 修复 → 验证通过"的完整过程归档到 `docs/solutions/`，供后续遇到相同问题时快速查阅，避免重复踩坑。

**执行提示：** 调用时无需额外参数，compound 会自动从当前对话上下文提取问题、根因和解决方案。若提示选择模式，**始终选择 Compact-safe（单次执行）** 以节省 context。

**衔接：** compound 完成（或跳过）后，进入步骤 4。

---

## 步骤 4：归档变更

**调用：** `Skill("opsx:archive")`

opsx:archive 会：
1. 检查 artifact 完成状态
2. 检查 delta specs，**始终选择"同步后归档（推荐）"**
3. 将 change 归档到 `openspec/changes/archive/YYYY-MM-DD-<name>/`

无需用户干预，所有确认提示均选推荐选项。

---

## 步骤 5：提交 & PR

**PR 检测：** 在执行前，先检查当前分支是否已有未合并的 PR：
```bash
gh pr list --head "$(git branch --show-current)" --state open --json number,title,url
```
若返回结果非空，说明当前分支已有 open PR，则**跳过创建新 PR**——仅执行 commit + push（代码会自动同步到已有 PR）。跳过 `commit-push-pr` skill，改为手动执行：
```bash
git add -A
git commit -m "<conventional commit message>"
git push
```

**调用前准备：** 先通过 `commit-push-pr` 创建 PR（此时 PR body 中截图部分用文件名占位），然后再上传截图并更新 PR body。

**调用：** `Skill("commit-commands:commit-push-pr")`

commit-push-pr 会自动：
1. 创建分支（如 `feature/{kebab-desc}`）
2. 暂存相关文件
3. 创建 conventional commit（中文风格）
4. push 并用 `gh pr create` 创建 PR

### 截图上传到 PR 描述

PR 创建后，将测试截图上传到 GitHub 并嵌入 PR body。`test-results/` 目录被 `.gitignore` 忽略，不能直接提交到仓库，需要通过 GitHub Release 临时托管截图文件。

**完整流程：**

**第一步：创建临时 Release**
```bash
git tag temp-screenshots
git push origin temp-screenshots
gh release create temp-screenshots --title "Test Screenshots (temp)" --notes "Temporary release for PR #<PR号> screenshots"
```

**第二步：上传所有截图为 Release Assets**
```bash
for img in "$TEST_RESULTS"/${SCREENSHOT_PREFIX}_*.png; do
  echo "Uploading $(basename "$img")..."
  gh release upload temp-screenshots "$img" --clobber
done
```

**第三步：验证上传完成**
```bash
gh release view temp-screenshots --json assets --jq '.assets | length'
```
确认数量与本地截图数量一致。

**第四步：构建带图片的 PR body 并更新**

截图的公开下载 URL 格式为：
```
https://github.com/<owner>/<repo>/releases/download/temp-screenshots/<文件名>
```

用 `gh pr edit <PR号> --body-file /tmp/pr-body.md` 更新 PR 描述，将截图以 Markdown 图片语法嵌入：

```markdown
## 测试截图

### 1. App 启动状态
| 截图A | 截图B |
|:---:|:---:|
| ![01](https://github.com/<owner>/<repo>/releases/download/temp-screenshots/01-xxx.png) | ![02](https://github.com/<owner>/<repo>/releases/download/temp-screenshots/02-xxx.png) |

### 2. 测试通过状态
...
```

**清理提示（PR 合并后可选）：**
```bash
gh release delete temp-screenshots -y && git push origin :temp-screenshots && git tag -d temp-screenshots
```

---

## 执行规范

- **不中断原则：** 所有步骤全部自动执行，不在中间停下来询问用户"是否继续"。
- **异常处理：** 若某步骤失败（如编译报错、测试失败），就地修复后继续，不放弃流程。
- **进度播报：** 每步开始时简短说明正在执行哪一步（"▶ 步骤 3/5：macOS UI 端到端测试"），让用户知晓进度。
- **上下文传递：** change 名称、改动文件列表等关键信息需在步骤间显式传递。
- **步骤 3.5 判断：** 严格按条件触发——只要步骤 3 出现过任何测试失败（即使最终修复通过），就必须执行 compound 记录经验；若测试一次通过则跳过，不影响主流程速度。
- **步骤 5 PR 检测：** 执行前用 `gh pr list --head` 检查当前分支是否已有 open PR。若已有 PR，仅 commit + push，不创建新 PR。
- **项目根目录锁定：** 步骤 3 开始时必须先执行 `PROJECT_ROOT=$(git rev-parse --show-toplevel)`，所有截图操作一律使用绝对路径 `$PROJECT_ROOT/test-results/`，禁止使用 `test-results/` 裸相对路径。
- **Python 环境选择：** AX UI/录音测试必须用 `arch -x86_64 /Users/wuzhiguo/projects/macos-ui-automation-mcp/.venv/bin/python3`；转录测试用系统 `python3`。两者不可互换。
- **AX 等待时间：** App 启动后等待 2s，Popover 动画后等待 1.5s，再查询 AX 树，避免因动画未完成导致元素找不到。
- **截图命名格式：** `{SCREENSHOT_PREFIX}_NN-描述.png`（前缀 = 分支名 + 日期YYMMDDHH），保存到 `$PROJECT_ROOT/test-results/`。
- **截图上传：** `test-results/` 被 `.gitignore` 忽略，步骤 5 中通过创建临时 GitHub Release → 上传截图为 Release Assets → 用下载 URL 嵌入 PR body 的方式实现。
