## ADDED Requirements

### Requirement: 转录文本与录音文件配对保存
系统 SHALL 在保存录音 WAV 文件的同时，将该录音会话期间产生的所有转录文本拼接后以同名 `.txt` 文件保存到同一目录（`~/Library/Application Support/VoicePepper/Recordings/`）。

#### Scenario: 有转录内容时保存文本文件
- **WHEN** 录音会话结束且 `AppState.entries` 中存在转录条目
- **THEN** 系统将所有转录条目的文本按时间顺序用换行符拼接，写入与录音文件同名的 `.txt` 文件

#### Scenario: 无转录内容时不创建空文件
- **WHEN** 录音会话结束但 `AppState.entries` 为空（如模型未加载完成）
- **THEN** 系统不创建 `.txt` 文件，仅保存录音 WAV 文件

### Requirement: 转录文本文件格式
转录文本文件 SHALL 为 UTF-8 纯文本格式，每条转录文本占一行，格式为 `[HH:mm:ss] 转录内容`。

#### Scenario: 多条转录写入同一文件
- **WHEN** 一个录音会话中产生了 3 条转录条目（时间分别为 10:00:01、10:00:05、10:00:10）
- **THEN** 生成的 `.txt` 文件包含 3 行，每行以时间戳开头

### Requirement: 转录文本文件加载
系统 SHALL 在加载录音列表时，自动检测每条录音是否有配对的 `.txt` 文件，并标记其可用性。

#### Scenario: 存在配对转录文本文件
- **WHEN** 录音目录中存在 `Recording_20250101_120000.wav` 和 `Recording_20250101_120000.txt`
- **THEN** 加载的 `RecordingItem` 的 `transcriptionURL` 指向该 `.txt` 文件

#### Scenario: 无配对转录文本文件（旧录音）
- **WHEN** 录音目录中仅存在 `Recording_20250101_120000.wav`，无对应 `.txt` 文件
- **THEN** 加载的 `RecordingItem` 的 `transcriptionURL` 为 nil

### Requirement: 转录文本文件删除
系统 SHALL 在删除录音文件时，同步删除配对的 `.txt` 文件。

#### Scenario: 删除有转录文本的录音
- **WHEN** 用户删除一条有配对 `.txt` 文件的录音
- **THEN** WAV 文件和 `.txt` 文件同时被删除

#### Scenario: 删除无转录文本的录音
- **WHEN** 用户删除一条无配对 `.txt` 文件的旧录音
- **THEN** 仅删除 WAV 文件，不报错
