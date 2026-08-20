# Apple CarPlay Video 权限申请中文指南

在通过 Apple Developer Portal ([https://developer.apple.com/contact/carplay/](https://developer.apple.com/contact/carplay/)) 提交 **CarPlay Video Entitlement**（车载视频播放权限）申请时，可参考以下对照表与文案。

---

### 一、 基础信息填写指引

| 申请表字段 | 建议填写内容 | 说明 |
| :--- | :--- | :--- |
| **Developer Name / Organization** | [你的开发者姓名 / 组织名称] | 必须与 Apple 开发者账号一致 |
| **Team ID** | [你的 10 位 Team ID] | 可在 Apple 开发者后台 Membership 查看 |
| **App Name** | `Vimu` | 应用名称 |
| **Bundle Identifier** | `com.kelvinsze.vimu`（或你自定义的 ID） | 必须与 Xcode 工程配置一致 |
| **App Category（应用类别）** | **Video** | 选择视频类（核心） |
| **Distribution Type（分发方式）** | **Development / Ad Hoc** | 私有测试自用；如后续考虑上架亦可说明 |

---

### 二、 核心申请描述文案

> **提示：** Apple 审核表单需提交英文，下方提供【英文提交原文】与【中文释义对照】。

#### 英文提交原文（可直接复制粘贴至表单 Description 栏）：

```text
Vimu is a lightweight local-network video player and media receiver designed for user-selected media. It supports HTTP/HTTPS video playback, HLS (.m3u8) streams, standards-compliant local-network media casting (UPnP/DLNA), and personal media streaming.

On supported CarPlay systems featuring "Video in Car", Vimu allows users to play their selected video content strictly when the vehicle indicates that video playback is safely available (e.g., when the vehicle is parked).

Safety and System Compliance:
- Vimu relies entirely on the native Apple CarPlay framework and the vehicle's system state (CPSessionConfiguration / video playback availability) to determine if video can be displayed.
- It does not attempt to spoof vehicle state, bypass driving safety restrictions, or enable video playback while the vehicle is in motion.
- When the vehicle transitions to a restricted state, Vimu immediately adheres to CarPlay guidelines by stopping or adapting video output.
- Vimu also natively supports AirPlay video streaming from its iOS playback interface.

Primary Use Case:
Allowing users to view their personal videos and cast media onto their CarPlay vehicle screen while parked at rest stops or charging stations.
```

#### 中文释义对照：

> Vimu 是一款轻量级的局域网视频播放器和媒体接收器，专门用于播放用户自行选择的媒体内容。它支持 HTTP/HTTPS 视频播放、HLS（.m3u8）流媒体、符合行业标准的局域网媒体投送（UPnP/DLNA）以及个人媒体服务串流。
>
> 在支持 Apple "Video in Car"（车载视频）的 CarPlay 系统上，Vimu 允许用户在车辆系统明确指示视频播放处于安全可用状态（例如车辆挂 P 档/停车状态）时播放选定的视频内容。
>
> **安全与系统合规性：**
> 1. Vimu 完全依赖 Apple CarPlay 原生框架与车机系统状态（`CPSessionConfiguration` 的视频可用性属性）来决定是否渲染视频。
> 2. 应用不会伪造车辆状态、不绕过任何行车安全限制，也绝不在车辆行驶过程中开启视频播放。
> 3. 当车辆状态变为限制行驶状态时，Vimu 会严格遵守 CarPlay 规范，立即暂停或调整视频输出。
> 4. Vimu 同时支持在 iPhone 端通过原生 AirPlay 投送视频。
>
> **主要使用场景：**
> 允许用户在服务区休息、充电桩补能或停车等待时，在支持的车载 CarPlay 大屏上浏览并播放个人媒体或投送视频。

---

### 三、 Apple 审核常见追问及中英文应答预案

#### 问题 1：视频内容的来源是什么？（How is video content sourced?）
- **英文回复：**
  > Content is strictly user-provided through direct URL entry, local network UPnP/DLNA casting from the user's own devices on the same local network, or the user's personal media server. Vimu does not host, distribute, or scrape unauthorized proprietary streaming content.
- **中文含义：**
  > 内容完全由用户自行提供，包括手动输入 URL、同一局域网内用户自有设备的 UPnP/DLNA 投送，或用户自建的个人媒体服务器。Vimu 本身不托管、不上架、不抓取任何未经授权的第三方专有流媒体内容。

#### 问题 2：应用如何确保行车安全？（How does Vimu handle driving safety?）
- **英文回复：**
  > Vimu strictly adheres to `CPSessionConfiguration.supportsVideoPlayback`. Video rendering is only engaged when the CarPlay session explicitly reports that the vehicle allows video presentation. If the vehicle moves or disables video, Vimu suspends video output without any attempt to bypass system restrictions.
- **中文含义：**
  > Vimu 严格监听并服从 `CPSessionConfiguration.supportsVideoPlayback` 状态。只有车机系统明确允许显示视频时才会激活视频渲染；一旦车辆移动或车机切断视频允许状态，Vimu 会立即响应并停止视频渲染，绝不尝试任何绕过行为。

#### 问题 3：当前的分发与测试计划是什么？（What is the distribution plan?）
- **英文回复：**
  > In the current stage, Vimu is built for Development and Ad Hoc validation on registered private test devices and vehicles (e.g. validating CarPlay Video in Car capability on Infiniti Q50L in-car multimedia systems).
- **中文含义：**
  > 当前阶段，Vimu 主要用于已登记 UDID 的自有测试设备与车辆环境下的 Development / Ad Hoc 验证（例如验证英菲尼迪 Q50L 后装车机系统上的 CarPlay Video in Car 支持能力）。

---

### 四、 避坑与审核重点提示

1. **绝对禁止出现的敏感词汇：**
   - 严禁在申请和沟通中使用 `mirror hack`（屏幕镜像破解）、`unlock CarPlay`（解锁 CarPlay）、`bypass driving lock`（绕过行车锁）、`jailbreak`（越狱）等词汇。
2. **强调被动服从：**
   - 始终向 Apple 强调：**Vimu 是 100% 被动服从 CarPlay 车机协议状态的，车机允许才显示，车机禁止立刻停止**。
3. **定位清晰：**
   - 强调自身是 **"Local Network Video Player & Media Receiver"**，归类于 **Video**。
