# Apple Multicast Networking 组播权限申请中文指南

在通过 Apple Developer 申请 **Multicast Networking Entitlement** (`com.apple.developer.networking.multicast`)（局域网组播收发权限）时，可参考本指南与对照文案。

- **申请入口：** [https://developer.apple.com/contact/request/networking-multicast](https://developer.apple.com/contact/request/networking-multicast)

---

### 一、 基础信息填写指引

| 申请表字段 | 建议填写内容 | 说明 |
| :--- | :--- | :--- |
| **App Name** | `Vimu` | 应用名称 |
| **Bundle Identifier** | `com.kelvinsze.vimu`（或你的 Bundle ID） | 必须与 Apple 开发者后台 App ID 一致 |
| **Primary Category（主类别）** | **Utilities / Media** | 实用工具 / 媒体类 |

---

### 二、 权限技术合理性与阐述（Justification）

> **提示：** Apple 审核表单需提交英文，下方提供【英文提交原文】与【中文释义对照】。

#### 英文提交原文（可直接复制粘贴至表单 Description 栏）：

```text
Vimu implements a standards-compliant UPnP/DLNA MediaRenderer designed to receive user-initiated video casting streams over the local Wi-Fi network.

Technical Requirement for Multicast:
- Standard UPnP Simple Service Discovery Protocol (SSDP) operates over UDP Multicast address 239.255.255.250 on port 1900.
- To be discovered as a media renderer by UPnP/DLNA controllers (such as local video apps, media servers, and mobile clients), Vimu must listen for SSDP M-SEARCH multicast discovery queries and broadcast periodic SSDP NOTIFY announcements on the local subnet.
- Without the multicast networking entitlement, incoming UDP multicast discovery packets are filtered by iOS, preventing standard DLNA controllers on the local network from discovering Vimu.

Privacy & Security Scope:
- Multicast is used strictly on the local Wi-Fi network for local device discovery and UPnP renderer control.
- Vimu does not use multicast for advertising, telemetry, user tracking, or any internet-facing communication.
- No personal user data is broadcast over multicast.
```

#### 中文释义对照：

> Vimu 实现了符合国际行业标准的 UPnP/DLNA 媒体渲染端（MediaRenderer），旨在接收用户在局域网内主动发起的视频投屏串流。
>
> **为什么必须使用 Multicast（组播）：**
> 1. 标准 UPnP 简单服务发现协议（SSDP）依赖于 UDP 组播地址 `239.255.255.250` 与端口 `1900` 进行局域网设备发现与宣告。
> 2. 为了能够被局域网内的第三方视频 App、媒体服务器或 DLNA 控制器发现，Vimu 必须能够监听组播地址上的 `M-SEARCH` 检索请求，并在局域网内广播周期的 `SSDP NOTIFY` 在线通知。
> 3. 如果没有组播网络权限（Multicast Networking Entitlement），iOS 系统会默认拦截此类 UDP 组播数据包，导致局域网内的其他设备完全无法搜寻和连接到 Vimu 投屏接收端。
>
> **隐私与安全边界：**
> 1. 组播通信仅在本地局域网内运行，严格用于设备发现与 UPnP 播放控制。
> 2. Vimu 绝不利用组播做广告推送、数据埋点、用户行为追踪或任何外网通信。
> 3. 组播数据包中绝不包含任何用户个人敏感隐私信息。

---

### 三、 工程配置说明

在配置好该权限后，项目需在两个位置体现：

1. **`Vimu.entitlements`：**
   ```xml
   <key>com.apple.developer.networking.multicast</key>
   <true/>
   ```

2. **`Info.plist`（本地网络权限弹窗说明）：**
   ```xml
   <key>NSLocalNetworkUsageDescription</key>
   <string>Vimu uses your local network to discover media servers and receive video casting requests from devices and apps on your network.</string>
   ```
   *(中文对应含义：Vimu 需要使用您的本地局域网，以便发现媒体设备并接收来自同网络下其他 App 与设备的视频投送请求。)*

---

### 四、 避坑与审核重点提示

1. **不要虚构 Bonjour 服务：**
   - DLNA / UPnP 使用的是标准 SSDP（UDP 1900 Multicast），而不是 mDNS/Bonjour。请勿为了申请权限而在 `Info.plist` 中乱填未实际使用的 `NSBonjourServices`。
2. **强调标准协议：**
   - 强调使用场景是 **"Standards-compliant UPnP/DLNA MediaRenderer"**，这属于 Apple 官方认可的组播合法使用场景之一。
