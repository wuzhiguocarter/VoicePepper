## MODIFIED Requirements

### Requirement: 录音完成后触发文件保存
录音流程 SHALL 在 VAD 分段完成时，除触发转录外，还异步触发 `RecordingFileService` 的文件保存操作，两者并行执行互不阻塞。

#### Scenario: VAD 分段同时触发转录和保存
- **WHEN** `AudioCaptureService.onSegmentComplete` 回调触发
- **THEN** `TranscriptionService` 接收样本进行转录，`RecordingFileService` 接收样本异步写盘，两者独立执行

#### Scenario: 保存失败不影响转录
- **WHEN** 文件写盘失败（如磁盘满）
- **THEN** 转录结果仍正常输出，不因写盘失败而中断或延迟
