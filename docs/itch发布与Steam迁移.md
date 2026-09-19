# itch.io 发布与未来 Steam 迁移

核验日期：2026-09-19<br>
适用工程：Mac 开发，Godot 4 + GDScript，Compatibility 渲染模式，单人 3D 办公室潜行游戏。

## 1. 当前决定

- 当前以 itch.io 为首个发布平台，优先制作电脑浏览器可玩的免费原型。
- 先验证一关闭环，再决定是否开展 Steam 商业发行。
- 维持一份 Godot 工程，按目标平台增加不同导出配置，不分别维护两套玩法。
- 本文是制作与发布准备说明，不表示已经建立商店页面、支付费用或完成上传。

## 2. itch.io 网页版如何交付

1. 从 Godot 导出 Web 构建，保留生成文件之间的名称和引用关系。
2. 以 `index.html` 为入口，将所需文件打包，入口放在 ZIP 根目录。
3. 本地通过 HTTP 测试服务器运行，不直接双击 HTML 文件作为验收方式。
4. 准备游戏标题、封面、实际游玩截图、操作、玩法介绍、浏览器支持和已知问题。
5. itch.io 项目类型选择 HTML Game，上传 ZIP，配置嵌入尺寸与全屏选项。
6. 在实际 itch.io 托管页面重新验证加载、键盘焦点、声音、暂停、重试和胜负，确认后公开页面。

itch.io 允许免费创建页面和上传内容，发布页面与进入搜索推荐是不同事情；发布容易不等于会自动获得流量。网页上传包的文件数量、大小等限制，在提交前按后台和最新文档复核。

来源：[itch.io 创建页面](https://itch.io/docs/creators/getting-started)、[HTML5 上传](https://itch.io/docs/creators/html5)、[创作者 FAQ](https://itch.io/docs/creators/faq)、[搜索与收录](https://itch.io/docs/creators/getting-indexed)。

## 3. 以后上 Steam，需要重写游戏吗？

通常不需要。这个判断基于 Godot 可以为同一工程添加多个导出配置；前提是核心玩法没有依赖只能在浏览器使用的接口或插件。

itch.io 是发布渠道，本身不限定开发技术，也可提供桌面下载版。因此：

- 如果 itch.io 已提供目标系统的桌面版，Steam 通常主要增加平台配置、商店资料和相应验证。
- 我们当前以网页为主，未来更合适的路线是从同一 Godot 工程导出桌面构建，再上传 Steam；无需把网页 ZIP 强行包装成桌面应用。

来源：[Godot 导出工程](https://docs.godotengine.org/en/stable/tutorials/export/exporting_projects.html)、[Windows 导出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_windows.html)、[macOS 导出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html)。

## 4. 哪些能复用，哪些需要补做

| 部分 | 从当前 itch.io 网页方案转 Steam 的工作 |
|---|---|
| 核心玩法 | 玩家移动、碰撞、领导行为、视野、警戒、关卡和胜负通常继续复用 |
| 资源 | 模型、材质、音效、对白通常继续使用，确认其授权覆盖发行用途 |
| 引擎与脚本 | 可继续使用 Godot、GDScript 和 Compatibility，不必为 Steam 更换语言或渲染器 |
| 导出包 | 增加拟支持的 Windows/macOS 等桌面导出配置，生成相应可执行构建 |
| 窗口与输入 | 检查窗口大小、全屏、键鼠、暂停、失焦，补上桌面退出游戏行为 |
| 声音与设置 | 检查音频行为、分辨率与设置持久化；不照搬浏览器交互假设 |
| 存档 | 保持读写接口和格式统一，但浏览器旧存档不会自动进入桌面版 |
| 系统测试 | 商店写明支持哪些系统，就实际测试哪些系统；本机 Mac 验证不能替代 Windows 验证 |
| Steam 发布 | 入驻、上传构建、配置内容仓库和启动项、商店页、内容调查、审核与发布日期 |
| 可选平台功能 | 成就、云存档、排行榜、创意工坊等按需求再接入，不作为当前原型依赖 |

桌面版可能有不同的性能和音频表现，因此“代码大多复用”并不等于“换个导出按钮就已完成适配”。

来源：[Godot Web 导出](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)、[Steam 构建上传](https://partner.steamgames.com/doc/sdk/uploading)、[Steam 审核](https://partner.steamgames.com/doc/store/review_process)。

## 5. Steam API 与上传工具的区别

Valve 明确说明，游戏内接入 Steamworks API 不是在 Steam 发布的必要条件。首版可以没有 Steam 成就、排行榜或云存档。

这不等于完全不使用 Steam 工具：通过 SteamPipe 上传构建时，会使用 Steamworks SDK 提供的上传工具。它和“在游戏代码里接入平台 API”是两件事。

上传工具支持 macOS，因此可以继续用 Mac 开发和上传；只有要支持 Windows 玩家时，才需要另外落实 Windows 测试环境。Steam 不要求每款游戏同时支持 Windows、macOS 和 Linux，但所有声明支持的系统都应通过测试。

来源：[Steamworks API 概览](https://partner.steamgames.com/doc/sdk/api?l=english)、[SteamPipe 上传文档](https://partner.steamgames.com/doc/sdk/uploading)、[审核要求](https://partner.steamgames.com/doc/store/review_process)。

## 6. 存档需要特别注意

使用 Godot 的 `user://` 能让同一套读写代码适用于多个平台：

- 网页版对应浏览器的 IndexedDB 存储，隐私模式或清除站点数据可能影响保存。
- 桌面版对应操作系统的用户应用数据目录。

所以在 itch.io 网页中玩过的进度，不会因为安装 Steam 版自动继承。若未来需要继承，再设计导出/导入存档；不必为此现在创建账号系统。

当前只有一关，主要保存音量等设置即可。以后加入进度时，建议给存档格式加版本号，并将关卡进度与机器相关的显示设置分开。这是维护建议，不是 Steam 强制规定。

若以后需要 Steam 云存档，可评估 Auto-Cloud：按文档配置同步路径即可，不一定需要在游戏中接 API。跨系统同步需要单独配置和验证；Steam 云存档也不会自动读取 itch.io 浏览器里的存档。

来源：[Godot 数据路径](https://docs.godotengine.org/en/stable/tutorials/io/data_paths.html)、[Web 存储限制](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html#using-cookies-for-data-persistence)、[Steam Cloud](https://partner.steamgames.com/doc/features/cloud)。

## 7. Steam 平台手续

根据当前官方文档，需要准备：

- 身份验证、银行账户和税务资料。
- 每款产品 100 美元 Steam Direct 费用。费用不可退款，但达到 1,000 美元调整后总收入后，可按规则在结算中回收。
- 商店介绍、截图等宣传素材，以及与成品一致的系统和功能说明。
- 内容调查，包括适用的 AI 生成内容披露。
- 可运行构建、启动项、发行包等配置，以及商店页和构建审核。
- 对最初几款产品，付款后至少 30 天等待期，且 Coming Soon 页面至少公开两周；这两段时间可重叠安排。

不要把审核预估工作日当作必定通过的承诺，也不要把 Steam 平台接受发布视为已经满足全部发行地区的法律要求。正式立项 Steam 发行时重新核对最新政策。

来源：[Steam Direct](https://partner.steamgames.com/steamdirect)、[审核流程](https://partner.steamgames.com/doc/store/review_process)、[内容调查](https://partner.steamgames.com/doc/gettingstarted/contentsurvey)。

## 8. 是否必须下架 itch.io 版本

普通情况下可以保留 itch.io 版本。itch.io 官方支持在其他商店同时销售以及发放 Steam 等外部商店的兑换码。以后若另签发行或独占协议，要按具体协议重新评估。

可选安排是保留 itch.io 免费原型，Steam 提供扩充后的正式版。两者的内容和价格差异必须说明清楚；不能把 Steam 买断版视为已经决定的商业方案。

来源：[itch.io 外部商店兑换码](https://itch.io/docs/creators/download-keys#external-keys-steam-etc)。

## 9. 现在应做的准备

1. 保持同一份工程，多平台导出配置分别管理。
2. 核心游戏逻辑使用引擎接口，避免依赖网页专属 JavaScript。
3. 平台差异集中处理，例如全屏、退出和之后的 Steam 功能。
4. 使用 `user://` 保存设置，避免硬编码用户电脑路径。
5. M0 优先验证 Web 导出，同时做一次本机桌面导出冒烟检查。
6. 从引入素材时就记录来源与授权。

当前不需要注册 Steamworks、支付 Steam Direct 费用、接入成就或云存档。先完成 itch.io 原型，将“未来能移植”落实为工程组织与小规模导出验证。
