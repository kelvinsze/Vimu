# 夸克网盘接入与多网盘聚合调研

调研日期：2026-09-10。范围仅限夸克公开的一手仓库、候选开源项目的官方仓库/文档，以及 Mivu 现有源码；未登录真实夸克账号，也未做播放压测。

## 结论

可以让 Mivu 播放夸克中的视频，但当前可行路径是 **用户自托管 OpenList（或兼容的 AList）作为适配层，再把其受控播放 URL 交给 Mivu**，而不是在 iOS 端直连夸克私有接口。

不建议把“夸克网盘原生直连播放”作为正式、稳定的产品承诺：截至本次调研，没有找到夸克面向第三方 App 的、文档化的视频直链/在线播放 API。夸克官方 GitHub 仓库确有“夸克网盘官方 Skill”，采用 OAuth 2.0 授权，但公开列出的能力是存储、下载、备份、分享、转存、移动、搜索与问答，未包含媒体流或播放 URL 合约。[官方 Skill README](https://github.com/quark-clouddrive/quarkclouddrive_offical/blob/main/README.md)

对于“一次集成常用网盘”，首选做 POC 的项目是 [OpenList](https://github.com/OpenListTeam/OpenList)，但它是一个需自行部署的多存储服务，不是可直接嵌入 iOS 的 SDK。它能统一挂载阿里云盘、百度、夸克、UC、115、迅雷、天翼、123、OneDrive、Google Drive、Dropbox、WebDAV、S3 等服务，并提供视频/音频预览、WebDAV、文件直链与 API 能力。[官方 README：存储清单与预览能力](https://github.com/OpenListTeam/OpenList/blob/main/README.md)

## 夸克：官方能力与稳定性判断

| 结论 | 一手证据 | 对产品的含义 |
| --- | --- | --- |
| 有官方授权能力，但公开 Skill 并不是视频播放 SDK/API。 | [官方 Skill](https://github.com/quark-clouddrive/quarkclouddrive_offical/blob/main/README.md) 明确其 OAuth 2.0 浏览器授权，且能力表仅列文件与 AI 管理功能。 | 可关注其后续开放能力；目前不能以此实现 Mivu 播放 URL。 |
| 普通 `Quark` 挂载依赖从浏览器开发者工具提取 Cookie，且是内置驱动而非外装插件。 | [OpenList Quark 驱动文档](https://github.com/OpenListTeam/OpenList-Docs/blob/main/pages/guide/drivers/quark.md) 的 Cookie 配置步骤；[驱动编译清单](https://github.com/OpenListTeam/OpenList/blob/main/drivers/all.go) 包含 `quark_uc`。 | 这是会过期、需重新登录的第三方适配方式；绝不能要求用户把 Cookie 提交给 Mivu 或云端。 |
| 普通 `Quark` 被文档标为强制本机代理，原因是限速；中转机先下载再转发。 | [同一驱动文档的限速与本机代理说明](https://github.com/OpenListTeam/OpenList-Docs/blob/main/pages/guide/drivers/quark.md)。 | 视频能播不等于体验可接受：服务器带宽、会员状态、跨网链路决定首帧与拖动体验，也会产生流量成本。 |
| 普通 `Quark` 驱动可按视频分类返回夸克转码地址或下载直链。 | [驱动元数据](https://github.com/OpenListTeam/OpenList/blob/main/drivers/quark_uc/meta.go) 与 [取链实现](https://github.com/OpenListTeam/OpenList/blob/main/drivers/quark_uc/driver.go)。 | OpenList 能提供现成的播放候选 URL；仍须在 Mivu 设备上逐一验证编解码、Range 与地址过期。 |
| `QuarkTV` 默认可 302，但只支持访问、下载两项；扫码后会保存 refresh token、device id、query token。 | [QuarkTV 段落](https://github.com/OpenListTeam/OpenList-Docs/blob/main/pages/guide/drivers/quark.md)。 | 不建议作为生产默认方案：其实现还会向明文 HTTP 的第三方端点交换令牌。[源码](https://github.com/OpenListTeam/OpenList/blob/main/drivers/quark_uc_tv/util.go) |
| 名为 `Quark Open` 的驱动被维护方明确标为“并非真正意义上的开放接口”，且缺少文档。 | [Quark Open 段落](https://github.com/OpenListTeam/OpenList-Docs/blob/main/pages/guide/drivers/quark.md)。 | 不应基于其 AppID/SignKey 设计生产功能或购买、交付 SLA。 |

因此，“可直接播放”的准确表述应是：**经用户控制的 OpenList 取得可访问的流/重定向地址后，Mivu 可以尝试播放；夸克侧认证、限速、地址有效期和接口变动均可能随时使它失效。**

## 候选开源方案

| 项目 | 许可 | 网盘覆盖与播放 | 夸克结论 | 建议 |
| --- | --- | --- | --- | --- |
| [OpenList](https://github.com/OpenListTeam/OpenList) | AGPL-3.0（[README](https://github.com/OpenListTeam/OpenList/blob/main/README.md)） | 覆盖中外大量网盘；自带视频/音频预览、文件直链、WebDAV 和 API。 | 有 Quark / QuarkTV / Quark Open 三种驱动；普通 Quark 强制本机代理，TV 可 302。 | **首选 POC**：作为独立、用户自托管的聚合后端。 |
| [AList](https://github.com/AlistGo/alist) | AGPL-3.0（[README](https://github.com/AlistGo/alist/blob/main/README_cn.md)） | 同样是多存储、视频/音频预览、WebDAV/直链的成熟实现。 | README 将夸克列为存储，但其免责声明也明确账号封禁、限速风险由用户承担。 | 仅用于既有部署兼容；新部署优先评估社区治理明确的 OpenList 分支。 |
| [rclone](https://rclone.org/) | MIT（[仓库 LICENSE](https://github.com/rclone/rclone/blob/master/COPYING)） | 对 Google Drive、OneDrive、Dropbox、S3、WebDAV 等是可靠的文件同步/挂载工具，可作后端运维补充。 | 官方支持清单当前没有 Quark；其官方仓库仍有“新增 Quark backend”的开放提案，说明尚非可用后端。[提案 #9661](https://github.com/rclone/rclone/issues/9661) | 不作为夸克播放方案；可与 OpenList 并用来处理其它已官方支持的云盘。 |

注意：OpenList/AList 的“支持”是服务端适配器能力，并不代表每个云盘都有官方授权 API，也不代表 iOS `AVPlayer` 对每种视频、重定向、Range 请求和鉴权方式都能成功。

## 与 Mivu 的最小集成边界

Mivu 已具备接收 HTTP/HTTPS 直链的播放入口：`HomeView` 将输入 URL 封装为 `.directUrl`，`MediaItem` 与 `PlaybackRequest` 可以携带请求头，`AVPlayerEngine` 也会把它们传给 `AVURLAsset`。相关源码：

- [HomeView.swift](../Sources/iPhone/Views/HomeView.swift) 的 `playInputUrl()`
- [MediaItem.swift](../Sources/MediaCore/MediaItem.swift) 的 `headers`
- [PlayerEngine.swift](../Sources/MediaCore/PlaybackCore/PlayerEngine.swift) 的 `PlaybackRequest`
- [AVPlayerEngine.swift](../Sources/MediaCore/PlaybackCore/AVPlayerEngine.swift) 的 `AVURLAssetHTTPHeaderFieldsKey`

建议的边界如下：

```text
用户在自己的 OpenList 登录/配置网盘
        │（夸克 Cookie 或 QuarkTV 扫码令牌仅留在该服务）
        ▼
OpenList：目录、鉴权、短效播放 URL、必要时本机代理
        │ HTTPS + 用户自有 OpenList 的访问令牌
        ▼
Mivu：浏览目录 → 获取单个文件播放 URL → 现有播放器播放
```

第一期应只做“连接用户自托管 OpenList + 浏览 + 播放”，不在 App 内收集夸克 Cookie、不代管用户网盘凭据、不把 OpenList 做成公共中转服务。这样复用现有播放器路径，且把最不稳定、最敏感的夸克适配隔离在用户可控制的服务端。

## 上线前必须验证的风险门槛

1. 使用真实夸克普通账户与会员账户各播放 MP4、MKV/H.265、HLS；验证首帧、暂停恢复、拖动（HTTP Range）、字幕、超过地址有效期后的重新解析。
2. 分别验证普通 Quark 的本机代理和 QuarkTV 的 302 路径，覆盖 Wi-Fi、蜂窝网络、App 后台恢复及 CarPlay/DLNA 投送；不得用 OpenList 网页预览成功替代 Mivu 实机验收。
3. OpenList 不得公网裸露：启用 HTTPS、每位用户独立身份与存储配置、最小权限、短效播放票据、日志脱敏；禁止把 Cookie、refresh token、播放 URL 查询参数写入诊断/崩溃日志。
4. `Quark Open` 不得直接用于生产：其默认在线刷新实现会把 refresh token 作为请求参数发给 `api.oplist.org`，同时本地刷新仍未实现。[源码](https://github.com/OpenListTeam/OpenList/blob/main/drivers/quark_open/util.go)；除非完成自有、可审计的刷新实现，否则禁用该驱动。
5. 采用 OpenList/AList 源码、修改其服务或对网络用户提供修改版时，先完成 AGPL-3.0 合规审查；AGPL 对经网络提供修改版服务有相应源码提供要求。[OpenList LICENSE](https://github.com/OpenListTeam/OpenList/blob/main/LICENSE) 同时复核夸克服务条款、账号与内容版权规则。OpenList 自身也提示其非网盘官方关联项目，并提示下游不要违反 AGPL。[README 声明](https://github.com/OpenListTeam/OpenList/blob/main/README.md)

## 决策建议

- **现在可做：** 建一个仅供内部/自托管测试的 OpenList 连接器 POC，并为夸克显示“实验性、依赖本机代理或 TV 令牌、可能限速/失效”的状态提示。
- **正式产品：** 把“多网盘”拆为两级：优先接入有稳定官方 OAuth/API 的服务；夸克仅作为用户自托管适配器，不承诺直连、速度或长期可用性。
- **不建议做：** 在 Mivu 内模拟网页登录、抓取 Cookie、硬编码 `drive.quark.cn` 私有端点，或把用户 Cookie 上传到 Mivu 服务端。

## 证据边界

本报告是源码/文档调研，不是法律意见，也不证明任一账号、区域、会员档位或视频文件已可播放。未改动业务代码，未运行 Xcode Build、模拟器、真实账户或网络播放测试。
