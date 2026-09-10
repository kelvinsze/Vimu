# Mivu iOS 播放核心渐进式改进方案

## 1. 修订结论与范围

本方案针对当前 Mivu 工程，而不是另起一个 Emby 播放器。当前工程同时支持 Emby、Jellyfin、普通 URL、DLNA、CarPlay、AirPlay 和系统远程控制；因此 `PlayerService` 继续是所有调用方的外部 seam，`MediaItem`、`PlaybackSession` 与 `MediaServerProtocol` 继续作为现有业务模型和服务端协议。

本轮已落地 Native AVPlayer adapter、可审计源码构建的 MPV adapter 与保守 Router：AVFoundation/libmpv 生命周期和观察逻辑分别收进 adapter，由 `PlayerService` 负责 session、Now Playing、远程命令、历史记录、DLNA/服务器上报及事件映射。默认仍走 Native；只有明确的非 Native 容器且框架可用时才尝试 MPV，失败回退 Native。现有 AirPlay、AVPlayerViewController、PiP、CarPlay 和 HTTP/DLNA 调用方保持兼容。

本轮明确不做：全量切换 mpv、自动转码重试、音视频轨道选择、HDR/Dolby Vision、CarPlay 自定义视频 surface、MPV 自定义 PiP/AirPlay、真机播放与分发许可证最终验收。

## 2. 目标架构

```text
UI / DLNA / CarPlay / HTTP
            │
            ▼
      PlayerService  ── session / Now Playing / history / reporting
            │
            ▼
        PlayerEngine seam
          ├── AVPlayerEngine       ← 默认实现，保留 Apple 能力
          └── MPVPlayerEngine      ← 明确容器的可选实现
```

`PlayerEngine` 是一个深模块：调用方只知道加载、控制和读取快照，不知道 AVFoundation、libmpv、FFmpeg、VideoToolbox 或服务端 API。状态变化通过事件流进入 `PlayerService`，UI 不直接监听引擎事件。

当前模型不重复创建 `PlayerItem` 或 `PlayerState`：

- `MediaItem`：应用层媒体模型。
- `PlaybackRequest`：内部、窄化的引擎输入，包含 URL、Header、起播点和可选容器提示。
- `PlaybackSession`：对 UI、DLNA、CarPlay 和 HTTP 暴露的统一业务快照。
- `PlaybackEngineSnapshot`：引擎产生的渲染器无关快照。

## 3. PlayerEngine 接口与线程模型

```swift
@MainActor
protocol PlayerEngine: AnyObject {
    var snapshot: PlaybackEngineSnapshot { get }
    var events: AsyncStream<PlaybackEngineEvent> { get }

    func load(_ request: PlaybackRequest)
    func play()
    func pause()
    func stop()
    func seek(to time: TimeInterval)
    func setPlaybackRate(_ rate: Float)
    func setVolume(_ volume: Float)
    func setMuted(_ isMuted: Bool)
}
```

接口不得出现 `AVPlayer`、`AVPlayerItem`、`mpv_handle`、FFmpeg 或服务端对象。`AVPlayer` 继续只通过 `PlayerService.player` 这个受控渲染 surface accessor 提供给 Native `PlayerView`；MPV renderer 通过独立 surface accessor 接入，不改变业务 seam。

线程与生命周期约束：

1. `PlayerService`、`PlayerEngine`、AVPlayer 命令、KVO 转换和事件消费统一在 Main Actor。
2. 引擎拥有 AVPlayer item 的 KVO、周期时间观察者和播放通知；引擎销毁或换 item 时先注销观察者，再释放 item。
3. 引擎只发送 `PlaybackEngineEvent`，`PlayerService` 是唯一把事件映射到 `PlaybackSession`、Now Playing、DLNA trace 和 server reporting 的模块。
4. MPV adapter 把 mpv callback 转换到同一 Main Actor 事件流，不得把 mpv C 类型泄漏到 Swift 调用方。

## 4. 当前实现：AVPlayerEngine

`Sources/MediaCore/PlaybackCore/AVPlayerEngine.swift` 负责：

- AVPlayer 创建与 external playback 配置；
- Header、起播点、网络直播暂停资源配置；
- AVPlayerItem 状态、buffer、loaded ranges 和 time control 观察；
- 250 ms 时间快照（4 Hz）；
- seek、rate、volume、mute、play/pause/stop；
- 播放结束、播放失败、time jump 和 error log 诊断事件。

`Sources/MediaCore/PlayerService.swift` 保留并负责：

- 既有公开控制方法和 `player` 渲染 surface；
- `PlaybackSession` 更新；
- audio session、Now Playing、MPRemoteCommandCenter；
- `PlaybackHistory`；
- DLNA trace/stage、Emby/Jellyfin session progress 上报；
- AirPlay、PiP、CarPlay 和 HTTP/DLNA 现有调用方兼容。

## 5. 服务端与候选流策略（后续阶段）

不要把播放核心绑定到 Emby。Emby、Jellyfin 和其他来源继续通过现有 `MediaServerProtocol` 与各自 adapter 产生播放信息。

`MediaPlaybackInfo` 现在通过 `MediaPlaybackCandidate` 保留有序候选，而不是只保留一个 URL：

```text
DirectPlay → DirectStream/Remux → Transcode
```

每个候选保留 URL、媒体源 ID 和 play session ID，并通过兼容性投影继续提供当前首选 URL/method 等字段。只有在后续阶段能够区分网络/认证、容器、codec、解码和渲染失败后，才允许请求 transcode-only PlaybackInfo；必须设置一次性重试标记，避免转码循环。Phase 2 只保存候选，不自动 fallback，也不修改服务端 endpoint、认证 Header 或请求行为。

## 6. MPV 集成与后续路线

本轮已完成来源明确、可复现构建的 `libmpv.xcframework` 生成与本地忽略接入；产物不提交仓库，使用 `scripts/build-libmpv-ios.sh` 重建。后续扩大覆盖面仍必须以真机能力验收和许可审查为前置。禁止直接下载或提交来源不明的预编译二进制，禁止把 FFmpegKit 或自建 FFmpeg pipeline 当作替代品。

当前稳定构建选择是：

```text
vo=libmpv
OpenGL ES Render API
hwdec=no
```

本方案不把 gpu-next 写成 iOS 稳定前提；除非锁定并维护经过验证的 fork，否则不得依赖它的 libmpv Render API。

MPV adapter 当前明确使用 `hwdec=no`；后续验收目标才是 `auto-safe`/VideoToolbox。验证顺序：真机 arm64 硬解、软件回退、字幕/libass、认证 Header、seek/rate、后台、AirPlay/PiP 影响、CarPlay scene 与 surface 生命周期。MPV 自定义 surface 不会自动继承 AVPlayerViewController 的 PiP/AirPlay 行为，因此 Native adapter 必须长期保留，或明确记录能力差异。

## 7. CarPlay、AirPlay 与 PiP 约束

- CarPlay 继续通过 `PlayerService` 控制，不把 `CPPlaybackConfiguration` 当作视频渲染实现。
- Native 路径继续使用 AVPlayer，所以保留 `AVPlayerViewController`、external playback、AirPlay route picker 和系统 PiP；MPV surface 的能力差异单独记录。
- MPV 阶段必须单独设计 render surface 的 scene 绑定、手机/CarPlay 切换、断连、后台和重连；不得因抽象完成就声称兼容。
- 自定义 MPV video surface 若需要 PiP，必须另行实现 sample-buffer content source 和 playback delegate，并进行真机验收。

## 8. 许可与供应链前置条件

在集成 MPV 前，必须锁定 mpv、FFmpeg、libass 的版本、源码、补丁、构建脚本和产物哈希，并完成静态/动态链接方式与 App Store 分发审查。`THIRD_PARTY_NOTICES.md` 至少记录版本、构建 flags、许可证、源码地址、修改内容和源码获取方式。

不能仅以 `-Dgpl=false` 推断整体合规；必须确认没有意外启用 GPL-only 组件，并由项目负责人完成 LGPL/GPL 义务审查。

## 9. 分阶段实施与验收

### Phase 0：基线与可行性

- 记录 dirty worktree，不覆盖 Vimu→Mivu、更名和 CarPlay 改动。
- 确认现有 `PlayerService`、`MediaItem`、`PlaybackSession`、`MediaServerProtocol` 的调用关系。
- 不下载依赖、不引入二进制。

### Phase 1：Native adapter（已完成首轮实现）

- 增加 `PlaybackCore/PlayerEngine.swift` 与 `AVPlayerEngine.swift`。
- 将 AVPlayer item/KVO/time observer/播放通知收进 adapter。
- `PlayerService` 继续作为外部 seam，映射 engine event 并保留既有业务行为。
- 增加纯模型/事件映射可行的低成本单测；本轮只做 parse、diff check 等低成本验证。

验收边界：静态检查通过只说明接口、引用和 diff 基本正确，不代表 Xcode 编译、签名、AirPlay、PiP、CarPlay 或真机播放通过。

### Phase 2：候选流保真（已完成模型与 selector 首轮实现）

- 在现有 `MediaPlaybackInfo` 中保留 DirectPlay → DirectStream → Transcode 有序候选。
- 继续提供兼容性的首选 URL、method、play session、media source 和 resume position 投影。
- Emby/Jellyfin 与 `resolvePlaybackItem` 继续只使用首选候选；本阶段不自动 fallback、不请求额外转码、不改变认证 Header 或 endpoint。
- 候选集合为空时保持 selector 返回 nil；新增纯模型测试覆盖顺序、首选项与无候选。

### Phase 3：MPV 可行性验证（已完成构建接入，设备验收未完成）

- 已验证可复现 XCFramework 的源码锁定、构建 flags、产物架构与 headers；license、真机硬解/软解、字幕与 Header 仍需验收。
- 在不替换 Native adapter 的前提下增加真实 MPV adapter 和渲染 surface。
- 逐项验证后台、AirPlay、PiP、CarPlay；未验证能力不得宣称完成。

### Phase 4：实验性 Router 与渐进启用

- 当前已建立实验性保守 `PlaybackRouter`，仅按明确容器提示选择 Native 或 MPV；扩大 MPV 覆盖面必须等待两个 adapter 各自完成验收。
- Router 按格式/能力 feature flag 选择 Native 或 MPV，不把实验性路由误当作全量切换。
- 记录 engine、候选、错误类别和转码回退指标。
- 完成 iPhone、DLNA、HTTP、CarPlay、AirPlay、PiP 的设备验收后，才考虑扩大 MPV 覆盖面。

## 10. 当前实施边界

本次实现包含 Phase 1 的 Native adapter、最小事件/快照 seam、Phase 2 的候选流保真，
以及 Phase 3 的可审计 libmpv XCFramework、MPV OpenGL ES Render API surface 和保守
Router。MPV 只处理明确的非 Native 容器提示；未知容器、通用服务器 `/stream`、DLNA
和框架不可用时均保持 Native。真机渲染、硬解、AirPlay/PiP/CarPlay 能力和分发许可证
仍未完成验收。
