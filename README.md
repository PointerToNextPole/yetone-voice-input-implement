# Voice Input Prompt Implementation

本仓库是 [yetone/voice-input-src](https://github.com/yetone/voice-input-src) 中给出的 macOS 菜单栏语音输入应用 prompt 的一个实现版本。

上游仓库的 README 提供了用于生成该应用的 prompt；本仓库则包含按照该 prompt 编写的 Swift/AppKit 源码、Swift Package Manager 配置、Makefile 构建脚本和 ad hoc 签名的 `.app` 打包流程。

## 功能

- 按住 Fn 键开始录音，松开 Fn 键后将识别结果注入当前聚焦的输入框。
- 通过全局 `CGEvent` tap 监听 Fn 键，并抑制 Fn 事件，避免触发系统表情符号选择器。
- 使用 Apple Speech Recognition framework 进行流式语音识别。
- 默认语言为简体中文 `zh-CN`，菜单栏支持切换：
  - English (`en-US`)
  - Simplified Chinese (`zh-CN`)
  - Traditional Chinese (`zh-TW`)
  - Japanese (`ja-JP`)
  - Korean (`ko-KR`)
- 录音时显示底部居中的无边框胶囊浮窗。
- 浮窗左侧五段波形由真实音频 RMS 电平驱动，右侧展示实时转写文本。
- 文本注入使用剪贴板和模拟 Cmd+V，并在 CJK 输入法下临时切换到 ASCII 输入源以提高粘贴可靠性。
- 支持 OpenAI-compatible API 对语音识别结果进行保守校正，适合中英混合场景。
- 以 `LSUIElement` 模式运行，仅显示菜单栏图标，不显示 Dock 图标。

## 系统要求

- macOS 14+
- Swift 5.10+
- Xcode Command Line Tools

运行时需要授予以下系统权限：

- Microphone
- Speech Recognition
- Accessibility
- Input Monitoring

## 构建

```sh
make build
```

构建产物位于：

```text
build/VoiceInput.app
```

Makefile 会优先尝试 `swift build -c release`。如果本机 Command Line Tools 存在 SwiftPM manifest 链接问题，会自动回退到直接 `swiftc` 编译，并生成标准 `.app` bundle。

构建完成后会使用 ad hoc signing：

```sh
codesign --force --deep --sign - build/VoiceInput.app
```

可使用以下命令验证签名：

```sh
codesign --verify --deep --strict --verbose=2 build/VoiceInput.app
```

## 运行

```sh
make run
```

首次运行后，请根据系统提示授予麦克风、语音识别、辅助功能和输入监控权限。权限授予后，可能需要重新启动应用。

## 安装

```sh
make install
```

该命令会将应用安装到：

```text
~/Applications/VoiceInput.app
```

## LLM Refinement

菜单栏中提供 `LLM Refinement` 子菜单：

- `Enabled`：启用或禁用 LLM 校正。
- `Settings...`：配置 API Base URL、API Key 和 Model。

API 需要兼容 OpenAI chat completions 格式。示例配置：

```text
API Base URL: https://api.openai.com/v1
Model: gpt-4o-mini
```

LLM prompt 采用保守校正策略：只修正明显的语音识别错误，例如中文同音错误或技术词汇误识别；不会改写、润色、翻译或删除看起来正确的内容。

如果 LLM 未启用、配置不完整或调用失败，应用会回退到原始语音识别结果。

## 项目结构

```text
Sources/VoiceInput/
  AppDelegate.swift              # 应用生命周期、菜单栏、权限和服务编排
  AppSettings.swift              # UserDefaults 设置和语言选项
  FnKeyMonitor.swift             # 全局 Fn 键事件监听
  SpeechTranscriber.swift        # Apple Speech 流式识别和 RMS 音频电平
  FloatingPanelController.swift  # 录音/校正状态胶囊浮窗
  TextInjector.swift             # 剪贴板粘贴注入和输入法临时切换
  LLMRefiner.swift               # OpenAI-compatible 文本校正
  SettingsWindowController.swift # LLM 设置窗口
  main.swift                     # 应用入口

Resources/
  Info.plist                     # Bundle 信息、隐私权限说明、LSUIElement

BuildSupport/
  empty-swift-module.modulemap   # 本机 CLT fallback 构建辅助文件
```

## 开发命令

```sh
make build    # 构建并 ad hoc 签名 .app
make run      # 构建并启动应用
make install  # 安装到 ~/Applications
make clean    # 删除 .build 和 build
```

## 来源说明

本仓库的目标是实现 [yetone/voice-input-src](https://github.com/yetone/voice-input-src) 中 README 所展示的 prompt。该上游仓库还链接了分发产物仓库；本仓库专注于实现源码和本地构建流程。

