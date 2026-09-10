# Mivu --- 私有版 CarPlay Video Receiver 开发与权限申请任务书

**项目名：** Mivu\
**定位：** Local Network Video Player & Receiver\
**目标平台：** iOS 27 / CarPlay Video in Car\
**分发方式：** Development / Ad Hoc 私有使用，第一阶段不上架 App Store\
**长期扩展：** Emby / Jellyfin 媒体库直连\
**版本：** v2.0 · 2026-08-20

------------------------------------------------------------------------

## 1. 项目目标

开发一个轻量级 iOS 视频播放器与局域网投送接收器 **Mivu**。

第一阶段核心目标：

1.  接收第三方 App 通过 DLNA/UPnP 发起的视频投送。
2.  使用 AVPlayer 播放收到的媒体 URL。
3.  在支持 Apple `Video in Car` 的 CarPlay
    系统上，于车辆允许视频播放时显示视频。
4.  以 Development / Ad Hoc 方式安装到自有设备，不以 App Store
    上架为前置目标。
5.  完全服从 CarPlay
    的车辆状态和视频可用性，不实现驾驶中视频解锁或车辆状态伪造。

长期目标：

-   增加 **Emby** 服务器连接。
-   增加 **Jellyfin** 服务器连接。
-   在 iPhone 与 CarPlay 上直接浏览个人媒体库并播放。
-   优先 Direct Play；必要时使用服务端转码。
-   让 Mivu 从"投屏接收器"扩展为轻量的个人媒体 CarPlay 客户端。

------------------------------------------------------------------------

## 2. 最重要的前置条件

### Gate 0：CarPlay Video entitlement

**这是项目的第一硬门槛。**

私有 IPA、Xcode Development、Ad Hoc 都不能绕过 CarPlay Video
entitlement。

必须由 Apple 批准对应 Managed Capability，并使 Development / Ad Hoc
provisioning profile 包含相应 entitlement，才能在未越狱 iPhone
真机上使用 CarPlay Video 能力。

因此开发顺序调整为：

``` text
提交 CarPlay Video entitlement
        ↓
并行开发普通播放器
        ↓
验证基础 DLNA Receiver
        ↓
CarPlay entitlement 获批
        ↓
最小 CarPlay Video PoC
        ↓
Q50L 实车 Gate
        ↓
深度优化 DLNA
        ↓
Emby / Jellyfin
```

如果 CarPlay Video entitlement 未获批准：

-   Mivu 的普通 iPhone 播放器仍可继续开发。
-   DLNA Receiver 仍可继续验证。
-   不继续投入大量 CarPlay 专用 UI 与兼容性开发。

------------------------------------------------------------------------

## 3. 权限申请

### 3.1 CarPlay Video entitlement

申请产品类别：

**Video**

建议申请描述：

> Mivu is a local-network video player and media receiver for
> user-selected media. It supports HTTP/HTTPS video, HLS streams,
> standards-compliant local-network media casting, and personal media
> servers.
>
> On supported CarPlay systems with Video in Car, Mivu allows users to
> play their selected video content when the vehicle indicates that
> video playback is available.
>
> Mivu relies entirely on CarPlay and the vehicle system to determine
> video availability. It does not spoof vehicle state, bypass driving
> restrictions, or enable video while driving.
>
> Mivu also supports AirPlay video streaming from its iPhone playback
> experience.

申请重点：

-   产品是 **Video Player / Media Receiver**。
-   内容由用户主动选择。
-   支持 AirPlay 视频输出。
-   CarPlay 仅作为停车状态下的视频播放界面。
-   不使用 `mirror hack`、`unlock CarPlay`、`bypass` 等表述。
-   如 Apple 允许只授予 Development / Ad Hoc
    capability，也可以接受，因为第一阶段为私有自用。

### 3.2 Multicast Networking entitlement

标准 DLNA/UPnP SSDP 使用：

``` text
239.255.255.250:1900
UDP Multicast
```

真机需要：

``` text
com.apple.developer.networking.multicast
```

建议申请描述：

> Mivu implements a standards-compliant UPnP/DLNA MediaRenderer for
> user-selected video content on the local network.
>
> UPnP SSDP discovery requires sending and receiving UDP multicast
> traffic on the local network. Multicast is used only for local device
> discovery and renderer control.
>
> Mivu does not use multicast for advertising, analytics, tracking, or
> Internet-facing communication.

### 3.3 Local Network Privacy

配置：

``` text
NSLocalNetworkUsageDescription
```

建议文案：

> Mivu uses your local network to discover media servers and receive
> video casting requests from devices and apps on your network.

如实际使用 Bonjour，再按真实 service type 配置
`NSBonjourServices`；不要为了权限申请虚构 Bonjour service。

------------------------------------------------------------------------

## 4. MVP 产品范围

### v0.1 --- Player Core

必须：

-   HTTPS 视频 URL
-   MP4 / MOV
-   HLS `.m3u8`
-   AVPlayer
-   Play / Pause
-   Seek
-   Duration / Position
-   基础错误处理
-   AirPlay 输出

暂不：

-   DRM 绕过
-   FFmpeg 全格式支持
-   IPTV / EPG
-   SMB
-   WebDAV
-   媒体刮削

### v0.2 --- DLNA Receiver

实现最小 UPnP MediaRenderer：

``` text
第三方 App
     ↓
SSDP Discovery
     ↓
Mivu MediaRenderer
     ↓
SetAVTransportURI
     ↓
AVPlayer
```

MVP 支持：

-   SSDP M-SEARCH
-   Device Description
-   AVTransport
-   `SetAVTransportURI`
-   `Play`
-   `Pause`
-   `Stop`
-   `Seek`
-   `GetTransportInfo`
-   `GetPositionInfo`

后续再做：

-   RenderingControl
-   GENA Event Subscription
-   DIDL-Lite metadata 完整兼容
-   Artwork
-   Volume synchronization

------------------------------------------------------------------------

## 5. CarPlay 最小 PoC

CarPlay entitlement 获批后，不立即开发完整 UI。

第一步只做：

``` text
测试视频 URL
      ↓
AVPlayer
      ↓
CarPlay Video
      ↓
Q50L
```

验证：

-   Mivu 是否出现在 CarPlay。
-   `CPSessionConfiguration.supportsVideoPlayback` 状态。
-   Q50L 后装模块停车时是否显示视频。
-   车辆不允许视频时系统如何处理。
-   有线 / 无线 CarPlay 是否存在差异。

### Gate 1

必须证明：

``` text
Mivu → CarPlay Video → Q50L
```

能够工作。

如果失败：

-   保存 CarPlay session 日志。
-   与 APTV 在同一 Q50L 环境下对照。
-   判断问题来自 entitlement、CarPlay API、后装模块还是 presentation
    配置。
-   Gate 未通过前不投入复杂 DLNA/媒体库开发。

------------------------------------------------------------------------

## 6. 投屏链路

Gate 1 通过后，把 DLNA Receiver 接到 CarPlay：

``` text
第三方视频 App
       ↓
DLNA / UPnP
       ↓
Mivu Receiver
       ↓
PlayerService
       ↓
AVPlayer
       ↓
CarPlay Video
       ↓
Q50L
```

### Gate 2

验证：

-   第三方 App 能发现 Mivu。
-   能把媒体 URI 发送给 Mivu。
-   Mivu 自动开始播放。
-   CarPlay 同步进入视频播放。
-   Pause / Seek 状态一致。

------------------------------------------------------------------------

## 7. 关键技术风险：同一 iPhone 投送

普通 DLNA 模型：

``` text
手机 A → 电视 B
```

Mivu 的重要目标可能是：

``` text
App A
  ↓
同一台 iPhone
  ↓
Mivu
  ↓
CarPlay
```

必须尽早实测：

-   iOS 是否允许其他 App 发现同机运行的 MediaRenderer。
-   SSDP multicast 是否会 loopback 到同一设备。
-   Mivu 切后台后 Receiver 是否仍可工作。
-   CarPlay scene 激活时 iPhone App 生命周期。
-   Wireless CarPlay 占用 Wi-Fi 后 multicast 路由行为。
-   Cellular + CarPlay Wi-Fi 并存时媒体 URL 的访问路径。

如果同机 DLNA 不稳定，保留备用输入：

-   Share Extension
-   URL Scheme
-   Universal Link
-   Clipboard URL
-   手动 URL
-   本地 HTTP handoff

不要让整个项目依赖单一的同机 SSDP 行为。

------------------------------------------------------------------------

## 8. 技术架构

``` text
Mivu
├── Application
│
├── MediaCore
│   ├── MediaItem
│   ├── PlaybackSession
│   ├── PlayerService
│   └── PlaybackHistory
│
├── Receiver
│   ├── SSDPService
│   ├── UPnPDevice
│   ├── AVTransportService
│   ├── SOAPParser
│   └── HTTPServer
│
├── Sources
│   ├── URLSource
│   ├── DLNASource
│   └── PersonalMedia
│       ├── MediaServerProtocol
│       ├── Emby
│       └── Jellyfin
│
├── iPhone
│   ├── Home
│   ├── Player
│   ├── ReceiverStatus
│   └── Servers
│
├── CarPlay
│   ├── Scene
│   ├── Browse
│   ├── NowPlaying
│   └── VideoPresentation
│
└── Diagnostics
    ├── Network
    ├── SSDP
    └── CarPlay
```

技术建议：

-   UI：SwiftUI
-   Playback：AVFoundation / AVPlayer
-   网络：Network.framework
-   Multicast：NWConnectionGroup
-   XML：Foundation XMLParser
-   HTTP/SOAP：Network.framework 或轻量 Swift HTTP Server
-   日志：OSLog
-   凭据：Keychain

------------------------------------------------------------------------

## 9. Emby / Jellyfin 长期功能

这部分安排在 CarPlay + DLNA 两个 Gate 都通过之后。

### 9.1 目标

Mivu 可以添加个人媒体服务器：

``` text
Mivu
 ├── Emby Server
 └── Jellyfin Server
```

用户能够：

-   添加 Server URL
-   登录
-   保存 token
-   浏览 Movies / TV Shows
-   查看 Recently Added / Continue Watching
-   搜索
-   查看影片详情
-   播放
-   Resume
-   切换字幕/音轨（后续）
-   CarPlay 浏览媒体库
-   CarPlay 停车状态直接播放

### 9.2 统一抽象

不要分别写两套 UI。

定义：

``` swift
protocol MediaServerProtocol {
    func authenticate(...)
    func libraries(...)
    func items(...)
    func itemDetail(...)
    func playbackInfo(...)
    func reportProgress(...)
}
```

然后：

``` text
MediaServerProtocol
      ├── EmbyClient
      └── JellyfinClient
```

因为 Jellyfin API 与 Emby 历史上高度相关，但实现时仍按各自当前公开 API
独立适配，避免假设完全兼容。

### 9.3 播放策略

优先级：

``` text
Direct Play
    ↓
Direct Stream
    ↓
Server Transcode
```

优先让 AVPlayer 直接访问媒体服务器提供的兼容 URL。

第一阶段优先支持：

-   H.264
-   HEVC
-   AAC
-   MP4
-   HLS

不为了支持所有 codec 在 iPhone 本地引入重型转码。

### 9.4 CarPlay 媒体库

后续 CarPlay 首页：

``` text
Mivu
├── Now Playing
├── Cast
├── Continue Watching
├── Movies
├── TV Shows
└── Servers
```

CarPlay 视频浏览保持简洁。

不把完整 Emby/Jellyfin 管理后台搬进 CarPlay。

------------------------------------------------------------------------

## 10. 开发阶段

### Phase 0 --- Day 1

-   [ ] 创建 Mivu Xcode Project
-   [ ] 注册 Bundle ID
-   [ ] 创建项目 Landing Page
-   [ ] 创建 Privacy Policy
-   [ ] 提交 CarPlay Video entitlement
-   [ ] 提交 Multicast Networking entitlement
-   [ ] 建立 Git repository
-   [ ] 建立 issue / milestone

**验收：** 两个权限申请已提交。

### Phase 1 --- Day 1--3

-   [ ] MediaItem
-   [ ] PlayerService
-   [ ] AVPlayer
-   [ ] MP4
-   [ ] HLS
-   [ ] Seek
-   [ ] AirPlay
-   [ ] 基础 Player UI

**验收：** 普通 iPhone 视频播放器稳定。

### Phase 2 --- Day 3--7

-   [ ] SSDP
-   [ ] Device Description
-   [ ] HTTP/SOAP Server
-   [ ] AVTransport
-   [ ] SetAVTransportURI
-   [ ] Play/Pause/Stop
-   [ ] Seek
-   [ ] Position / Transport State

**验收：**

``` text
DLNA Controller → Mivu → AVPlayer
```

工作。

### Phase 3 --- 等待 entitlement

-   [ ] 同机投送实验
-   [ ] Wireless CarPlay 网络研究
-   [ ] Receiver 生命周期
-   [ ] URL Scheme
-   [ ] Share Extension
-   [ ] Diagnostics
-   [ ] 错误处理

不要在 entitlement 未批前过度开发 CarPlay UI。

### Phase 4 --- CarPlay entitlement 获批

-   [ ] 更新 App ID Capability
-   [ ] 重新生成 Development Profile
-   [ ] 确认签名 entitlement
-   [ ] 创建最小 CarPlay scene
-   [ ] 读取 `supportsVideoPlayback`
-   [ ] 测试固定视频 URL
-   [ ] Q50L 实车

**Gate 1：**

``` text
AVPlayer → CarPlay Video → Q50L
```

成功。

### Phase 5 --- Cast → CarPlay

-   [ ] Receiver 与 CarPlay PlayerService 打通
-   [ ] 收到投送自动更新播放 session
-   [ ] CarPlay Now Playing
-   [ ] Pause/Seek 同步
-   [ ] 断开/重连
-   [ ] 来电
-   [ ] 后台
-   [ ] 网络切换

**Gate 2：**

``` text
第三方 App → DLNA → Mivu → CarPlay → Q50L
```

稳定工作。

### Phase 6 --- Emby / Jellyfin

Gate 1 + Gate 2 均通过后开始。

-   [ ] MediaServerProtocol
-   [ ] Server management
-   [ ] Keychain credentials
-   [ ] Jellyfin authentication
-   [ ] Emby authentication
-   [ ] Library API
-   [ ] Item detail
-   [ ] PlaybackInfo
-   [ ] Direct Play
-   [ ] Resume / progress reporting
-   [ ] Continue Watching
-   [ ] Search
-   [ ] CarPlay Browse

**验收：**

``` text
Emby/Jellyfin
      ↓
Mivu
      ↓
AVPlayer
      ↓
CarPlay Video
```

无需 DLNA 中转即可播放个人媒体。

------------------------------------------------------------------------

## 11. 私有分发策略

第一阶段不提交 App Store。

目标：

``` text
Apple Developer Account
       ↓
Approved Managed Capabilities
       ↓
Development / Ad Hoc Profile
       ↓
Mivu IPA
       ↓
Registered iPhone
```

优先：

1.  Xcode Development 安装
2.  稳定后生成 Ad Hoc IPA
3.  仅安装到登记 UDID 的自有测试设备

注意：

**私有 IPA 不能绕过 CarPlay Video entitlement。**

如果 Apple 只批准 Development 而不批准 Ad Hoc：

-   保持 Xcode Development 自用即可。
-   不把 Ad Hoc 作为项目成败条件。

------------------------------------------------------------------------

## 12. 安全边界

Mivu 不实现：

-   Driving video unlock
-   Parking state spoofing
-   CarPlay vehicle state modification
-   DRM bypass
-   FairPlay/Widevine 破解
-   iOS 私有 API
-   未授权内容抓取
-   强制整屏镜像

视频是否可在 CarPlay 显示，由 CarPlay / vehicle capability 决定。

------------------------------------------------------------------------

## 13. Q50L 实车测试矩阵

  场景                          预期
  ----------------------------- ---------------------------
  CarPlay 连接                  Mivu 正常出现
  `supportsVideoPlayback`       正确返回车机能力
  停车                          视频可显示
  车辆禁止视频                  Mivu 不绕过系统限制
  有线 CarPlay                  正常
  无线 CarPlay                  正常
  DLNA 投送                     自动开始播放
  Seek                          iPhone / CarPlay 状态同步
  来电                          合理暂停/恢复
  CarPlay 断开                  iPhone 正确接管/停止
  CarPlay 重连                  Session 不异常
  Cellular + Wireless CarPlay   媒体 URL 可正常访问
  Emby/Jellyfin                 Direct Play 正常
  Emby/Jellyfin Resume          播放进度同步

------------------------------------------------------------------------

## 14. 项目风险

### 高风险：CarPlay Video entitlement

解决：

-   Day 1 申请。
-   entitlement 未批前限制 CarPlay 专用开发投入。

### 高风险：同机 DLNA

解决：

-   尽早 PoC。
-   保留 Share Extension / URL Scheme / URL 输入。

### 高风险：Wireless CarPlay 网络拓扑

解决：

-   Diagnostics 记录 active interface。
-   必要时增加 local HTTP proxy。

### 中风险：第三方视频需要 Headers / Cookies

v0.2 后增加：

-   User-Agent
-   Referer
-   Authorization
-   Cookie
-   Local Proxy

### 中风险：Emby/Jellyfin codec

解决：

-   Direct Play 优先。
-   不兼容时使用服务端转码。
-   不在 iPhone 第一阶段做重型本地转码。

------------------------------------------------------------------------

## 15. 最终路线图

``` text
Mivu 0.1
Video Player
    ↓
Mivu 0.2
DLNA Receiver
    ↓
CarPlay entitlement
    ↓
Mivu 0.3
CarPlay Video PoC
    ↓
Q50L Gate
    ↓
Mivu 0.4
DLNA → CarPlay
    ↓
Mivu 0.5
投屏兼容性 / Headers / Proxy
    ↓
Mivu 0.6
Jellyfin
    ↓
Mivu 0.7
Emby
    ↓
Mivu 1.0
Private Stable Release
```

------------------------------------------------------------------------

## 16. 项目完成定义

Mivu 第一阶段完成的标准不是"功能很多"，而是下面这条链路稳定：

``` text
第三方 App
     ↓
DLNA
     ↓
Mivu
     ↓
AVPlayer
     ↓
CarPlay Video
     ↓
Q50L
```

第二阶段完成标准：

``` text
Emby / Jellyfin
       ↓
Mivu Media Library
       ↓
Direct Play / Server Transcode
       ↓
AVPlayer
       ↓
CarPlay Video
```

两个路径共用同一个
`MediaCore + PlayerService + CarPlay presentation`，避免后期形成两套播放器架构。

------------------------------------------------------------------------

## 17. 官方参考

-   Apple CarPlay Developer\
    https://developer.apple.com/carplay/

-   Requesting CarPlay Entitlements\
    https://developer.apple.com/documentation/carplay/requesting-carplay-entitlements

-   Apple Managed Capabilities\
    https://developer.apple.com/help/account/reference/provisioning-with-managed-capabilities/

-   Multicast Networking Entitlement\
    https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.multicast

-   Local Network Privacy\
    https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy

-   Jellyfin API Documentation\
    https://api.jellyfin.org/

-   Emby API Documentation\
    https://dev.emby.media/
