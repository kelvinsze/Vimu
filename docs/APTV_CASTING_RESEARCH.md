# APTV 车内 DLNA 投屏研究

研究日期：2026-09-03

## 结论

APTV 已经公开实现了「第三方 App → APTV → CarPlay」的 DLNA 接收链路，并另外提供「蜂窝网络投屏」和「增强投屏模式」。因此，**“iPhone 断开普通 Wi‑Fi 后，同机 DLNA 接收绝对不可能”并不准确**。

但公开资料没有披露其网络实现。APTV 官方只明确说，部分视频 App（举例小红书）在无线 CarPlay 和有线 CarPlay + 蜂窝网络下需要开启增强投屏；官方确认 APTV 能接收 B 站投屏，不等于官方确认「B 站在纯蜂窝网络下一定能发现 APTV」。用户已经观察到的成功场景，需要按有线/无线 CarPlay 和实际接口状态进一步复现。

## 已证实事实

1. APTV 官网把 `@AptvPlayerChannel` 列为官方通知频道，因此该频道的版本公告可作为开发者公开说明。[APTV 官网](https://aptv.app/)
2. 测试版 `9.9.9 (493)` 公告称「CarPlay 新增 DLNA 投屏功能」，可把支持投屏的 App 内容投到车机。[官方公告](https://t.me/AptvPlayerChannel/597)
3. 下一版 `9.9.9 (494)` 增加「蜂窝网络投屏」和投屏历史。该官方帖可直接核验的兼容性说明仅为：部分视频 App（举例小红书）在无线 CarPlay 和有线 CarPlay + 蜂窝网络下需要开启增强投屏。[官方公告](https://t.me/AptvPlayerChannel/598)
4. 正式版 `1.5.9` 公告列出「CarPlay 支持第三方 App 投屏」和「增强投屏模式」。[官方公告](https://t.me/AptvPlayerChannel/599)
5. 后续测试版明确增加「接收 B 站投屏时渲染弹幕」，证明 APTV 的接收端已经针对 B 站协议/元数据做过兼容。[官方公告](https://t.me/AptvPlayerChannel/600)
6. App Store 商品页确认 APTV 支持 iOS（含 CarPlay）及 AirPlay/DLNA，但未说明蜂窝或增强模式的实现。[App Store](https://apps.apple.com/cn/app/aptv/id1630403500)
7. APTV 的公开 GitHub 仓库只有介绍与测试播放列表，没有当前 App 源码；README 甚至仍把 DLNA 列为后续计划，明显滞后于上述版本公告，不能用来还原实现。[GitHub](https://github.com/Kimentanm/aptv)

> 注：网络上能找到包含「多数视频 App 检查 Wi‑Fi」「仅少部分 App（小红书、SenPlayer）可用」「优先有线 CarPlay + Wi‑Fi/热点」的转载文案，但目前可公开核验的来源是第三方频道，不是 APTV 官方 598 帖，因此本文不把这些扩展表述作为第一方结论。

## Apple 与协议边界

- UPnP 的标准发现过程是控制端向 `239.255.255.250:1900` 发送 SSDP `M-SEARCH`，设备以单播回复并给出 `LOCATION`；之后设备描述和 SOAP 控制走 HTTP。[UPnP Device Architecture 2.0](https://openconnectivity.org/upnp-specs/UPnP-arch-DeviceArchitecture-v2.0-20200417.pdf)
- Apple 把 Wi‑Fi、以太网视为本地网络接口，但不把蜂窝 WWAN 或 VPN 视为本地网络；所有组播地址仍属于本地网络地址。iOS 上收发组播还需要本地网络授权及 multicast entitlement。[TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- Apple 的 peer-to-peer Wi‑Fi 需要通信双方采用相应 API，且底层协议不向第三方开放。它无法直接解释一个未经配合修改的 Bilibili App 如何发现同机 APTV。[TN3151](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api)
- CarPlay 的视频呈现能力与 DLNA 发现是两层问题：APTV 先在 iPhone 内接收媒体，再通过自己的 CarPlay 场景显示；车机本身不必是 Bilibili 看到的 DLNA 接收器。Apple 官方的视频 App/车内 AirPlay 能力还受车型支持与非驾驶状态限制。[Apple CarPlay](https://developer.apple.com/carplay/)

## 场景区分

| 场景 | 公开证据支持的判断 |
| --- | --- |
| 同一台 iPhone，普通 Wi‑Fi，有线 CarPlay | 属于标准 DLNA 局域网路径；公开资料确认 APTV 支持第三方 App 投屏，但没有提供各发送 App 的完整兼容表。 |
| 同一台 iPhone，仅蜂窝，有线 CarPlay | APTV 接收端具备蜂窝模式；官方称部分 App 需开增强投屏，但没有把 Bilibili 列为纯蜂窝保证兼容。 |
| 同一台 iPhone，无线 CarPlay | 无线 CarPlay 会占用 Wi‑Fi 链路，但状态栏/默认上网路径不能完整代表系统仍有哪些接口。APTV 是否利用 CarPlay 接口、本机回环或其他方式，官方未披露。 |
| 两台设备，共用车载热点/随身路由器 | 属于普通同局域网 DLNA；发送端与 APTV 所在 iPhone 都必须可在该局域网互访。 |
| 两台设备，各用各的蜂窝网络 | 没有证据表明 APTV 能跨运营商网络完成 SSDP 发现；标准 SSDP 组播不会跨互联网路由。 |
| 一台开个人热点、另一台加入 | 可能形成可用局域网，但 iOS 热点的组播与客户端隔离行为需要真机验证，不能只根据“已连热点”判断。 |

## 对 APTV 实现的合理推断（未证实）

最可能的总体结构仍是一个运行在 iPhone 内的 DLNA MediaRenderer：Bilibili 发出 SSDP 搜索，APTV 返回设备描述和 SOAP 控制地址，然后由 APTV 获取媒体 URL 并播放到自己的 CarPlay 视频界面。

为适配没有普通 Wi‑Fi 的同机发送，APTV 可能做了以下一项或多项：

- 允许 SSDP 数据包在本机回环，并同时监听不同网络接口；
- 根据收到 `M-SEARCH` 的入口接口选择可被发送 App 回连的 `LOCATION`，而不是固定选一个 IP；
- 在蜂窝、无线 CarPlay、普通 Wi‑Fi 切换时重建监听和广告；
- 「增强投屏」通过本地 HTTP 代理/URL 转发处理发送 App 的接口绑定、Header、Cookie、重定向或媒体地址兼容。

以上没有 APTV 源码、抓包或开发者说明支持，不能当作实现事实。尤其不能简单归因于 `includePeerToPeer` 或 CarPlay 自带 DLNA 通道。

## 与 Mivu 当前实现的对照

当前 Mivu 已具备 multicast entitlement、BSD UDP、`NWConnectionGroup`、SSDP 回复和 HTTP/SOAP 服务，但仍有几个与该场景直接相关的待验证点：

- [`NetworkHelper.getWiFiAddress()`](../Sources/Receiver/HTTPServer.swift) 固定优先 `en0`，再取 `pdp_ip0`/`lo0`；它没有根据每个 SSDP 请求实际进入的接口生成 `LOCATION`。
- [`SSDPService`](../Sources/Receiver/SSDPService.swift) 使用 `IP_ADD_MEMBERSHIP` 的默认接口和默认 Network.framework 路径，没有记录入站接口索引、源地址、回环选项或发送失败码。
- 网络变化后没有看到基于 `NWPathMonitor` 的按接口重建；无线 CarPlay 建链或 Wi‑Fi 断开后，启动时选定的组播成员关系可能已经失效。
- 当前日志只能证明解析到 `M-SEARCH`，不足以区分「Bilibili 没发」「内核没把包交给 Mivu」「Mivu 回了错误接口/IP」「Bilibili 无法访问 `LOCATION`」四种故障。

这不是实现结论，而是下一轮真机对照实验应优先检查的差异。

## 最小验证方案

先不要猜 APTV 私有实现。用同一台 iPhone、同一辆车、同一 Bilibili 版本，对 APTV 与 Mivu 分别记录以下四组：

1. 有线 CarPlay + 普通 Wi‑Fi；
2. 有线 CarPlay + 仅蜂窝；
3. 无线 CarPlay；
4. 不连 CarPlay + 仅蜂窝。

每组至少记录：系统可用接口名/IP、`M-SEARCH` 是否收到及其源 IP/入口接口、回复的目标地址与 `LOCATION`、`description.xml` 是否被请求、SOAP `SetAVTransportURI` 是否到达。若 APTV 成功而 Mivu 失败，这些证据可以把差异收敛到发现、回连地址或取流兼容中的某一层。

最值得先验证的实现方向是：**按接口监听与回复 + 基于入站接口选择 `LOCATION` + 网络切换重建服务 + 明确的同机回环模式**；「增强投屏」媒体代理应在确认发现和 SOAP 链路已成功后再研究。

## Mivu 实测记录

### 2026-09-03：第一轮非 VPN 多路径发现

- 用户实测：连接普通 Wi-Fi 时，Bilibili 可以发现并投屏到 Mivu。
- 用户实测：关闭 Wi-Fi 后，Bilibili 的设备列表找不到 Mivu。
- 判断：标准局域网 SSDP 链路有效；主动回环单播与本机地址单播未解决无 Wi-Fi 发现。
- 下一轮：显式让 SSDP listener 加入 `lo0` 的 multicast membership，并从 loopback 接口向 `239.255.255.250:1900` 发送带独立 `via=loopback-multicast` 标记的宣告；继续保留其他路径并行运行。
- Boost/VPN：用户观察 APTV Boost 会建立本机 VPN；当前阶段不实现。

### 2026-09-03：第二轮控制成功、CarPlay 未呈现

- 用户实测：关闭 Wi-Fi 后，iPhone 端已经提示投屏，但 CarPlay 没有收到播放内容。
- 判断：本机发现与 `SetAVTransportURI` 控制链路已经建立，问题转移到媒体取流或 CarPlay 呈现阶段。
- SDK 核对：`CPPlaybackConfiguration` 的视频呈现只在用户选择对应 CarPlay 列表项后发生；DLNA 投送不会产生这次列表选择。
- 当前增强：收到 `SetAVTransportURI` 后刷新 CarPlay 当前项目，并通过公开的 `CPNowPlayingTemplate` 主动进入播放页；日志分开记录“控制已接收”“媒体已就绪”“CarPlay 播放页已呈现”，不再把收到控制直接标记为投屏成功。
