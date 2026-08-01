# 方圆里 MVP v1.0 技术选型与工程实施方案 v0.1

> 文档状态：工程决策初稿
> 日期：2026-07-28
> 对应资料：产品规格、数据模型与系统架构、API 契约 v0.1

---

## 0. 本阶段结论

方圆里正式工程采用：

| 层级 | 选择 |
|---|---|
| iPhone / Android App | Flutter 3.44 稳定通道 |
| 后端语言 | TypeScript |
| 后端框架 | NestJS 11 + Fastify |
| 后端运行时 | Node.js 24 LTS |
| 数据库 | PostgreSQL 18 + PostGIS |
| 数据访问 | 统一 `DatabaseService` + `pg`；Kysely 渐进引入，迁移以 SQL 为准 |
| 实时通信 | NestJS WebSocket 网关，JSON 事件遵守 AsyncAPI |
| 缓存和实时状态 | 腾讯云分布式缓存数据库（兼容 Redis）7.x，MVP 标准架构 |
| 媒体 | 腾讯云 COS 私有桶 + 短期预签名上传/读取 |
| 后台任务 | Redis 队列 + 独立 Worker 进程 |
| 运营后台 | React + TypeScript + Vite |
| 接口契约 | OpenAPI + AsyncAPI |
| 部署 | Docker 容器 + 腾讯云 CVM，生产数据库/缓存使用托管服务 |
| 日志与监控 | 结构化日志 + 腾讯云 CLS + 健康检查和告警 |

这套选择不是追求“技术最多”，而是为以下目标服务：

- 早期一支小团队也能维护；
- 地理、聊天、媒体和权限可以正确实现；
- 修改产品规则时只改对应模块；
- 能在腾讯云逐步扩容；
- 将来用户增长后可以拆分实时消息、媒体和搜索；
- 不要求董事长具备编程基础。

---

## 1. 官方版本依据

### 1.1 Flutter

Flutter 官方文档在 2026 年 5 月发布 Flutter 3.44，当前文档对应 3.44.7。正式项目使用 Flutter 3.44 稳定通道，创建工程时再锁定当时最新的 3.44.x 补丁版本，不使用 beta 或 master。

官方资料：

- <https://docs.flutter.dev/release/whats-new>
- <https://docs.flutter.dev/install/upgrade>

### 1.2 Node.js 与 NestJS

Node.js 官方把 24 标记为 LTS；26 在当前时间仍为 Current。生产项目应使用 LTS，因此选择 Node.js 24，不追逐 Node.js 26。

NestJS 11 官方要求 Node.js 20 或更高，并建议使用最新 LTS。NestJS 11 同时支持 Fastify 5。

官方资料：

- <https://nodejs.org/en/about/previous-releases>
- <https://docs.nestjs.com/migration-guide>
- <https://docs.nestjs.com/deployment>

### 1.3 PostgreSQL

PostgreSQL 官方对每个大版本支持 5 年。PostgreSQL 18 支持至 2030 年 11 月；腾讯云数据库 PostgreSQL 当前支持 11–18。

选择 PostgreSQL 18，但购买前必须在目标地域和目标实例上确认 `postgis` 可创建。腾讯云官方提供 PostgreSQL + PostGIS 的附近对象方案，也提供查询可用扩展和 `CREATE EXTENSION` 的流程。

官方资料：

- <https://www.postgresql.org/support/versioning/>
- <https://cloud.tencent.com/document/product/409/127570>
- <https://cloud.tencent.com/document/product/409/121744>
- <https://intl.cloud.tencent.com/zh/document/product/409/47392>

### 1.4 腾讯云 Redis 与 COS

腾讯云“云数据库 Redis”已更名为“腾讯云分布式缓存数据库（兼容 Redis）”。MVP 使用 Redis 7.x 标准架构 1GB 起步，不购买集群版。官方规格中 256MB 更适合测试，不建议生产。

COS 默认资源为私有；上传使用短期预签名 URL 或临时密钥，并遵守最小权限。消息媒体的 3 天、15 天、2 个月等删除不能完全依赖 COS 每日生命周期扫描，业务数据库仍保存精确 `expiresAt`，COS 生命周期作为兜底清理。

官方资料：

- <https://cloud.tencent.com/document/product/239/129788>
- <https://cloud.tencent.com/document/product/239/17952>
- <https://cloud.tencent.com/document/product/436/30749>
- <https://cloud.tencent.com/document/product/436/35651>
- <https://cloud.tencent.com/document/product/436/17028>

---

## 2. 为什么选择 Flutter

### 2.1 对本项目的好处

- 一套主要代码支持 iPhone 和 Android；
- 页面、聊天输入框、动态图片布局和自定义选择器可统一；
- iPhone 真机测试后，Android 不需要重新写一整套界面；
- 地图、相机、相册、麦克风、推送、WebSocket 和本地安全存储均有成熟接入方式；
- 适合当前原型已经反复验证的自定义 UI。

### 2.2 不选择微信小程序

方圆里的核心依赖持续定位、实时聊天、语音、相机、相册、系统推送、后台状态和复杂个人隐私。小程序可以用于后续传播或轻量入口，但不适合作为第一版完整产品主体。

### 2.3 不选择分别开发 iOS 和 Android 原生

原生体验上限高，但第一版需要两套客户端工程和更多开发成本。方圆里的难点主要在地理规则、关系状态、实时消息和运营治理，而不是必须依赖某个 iOS 独占 UI。Flutter 更适合当前阶段。

### 2.4 iOS 构建限制

腾讯云普通 Linux 服务器不能完成 iOS 的最终编译、签名和真机安装，因为这些步骤需要 macOS、Xcode 和 Apple 签名环境。

推荐工作方式：

```text
腾讯云 / Git 仓库
  ├─ 保存全部正式源码
  ├─ 运行后端、数据库迁移、测试和 Android/Linux 构建
  └─ 生成待测试代码版本

董事长的 Mac
  ├─ 只拉取指定版本
  ├─ 使用 Xcode 构建并安装到 iPhone
  └─ 不保存生产数据库和服务器密钥
```

以后如果不想依赖本机，可以购买合法的 macOS 云构建服务，但第一阶段没有必要增加这项成本。

---

## 3. 为什么选择 TypeScript + NestJS

### 3.1 与 Go、Java 的比较

| 方案 | 优点 | 当前阶段不足 | 结论 |
|---|---|---|---|
| TypeScript + NestJS | 开发快、模块化明确、WebSocket 和后台管理生态好 | 极限性能不如精心优化的 Go | 采用 |
| Go | 性能高、部署简单、并发好 | 业务 DTO、管理后台和快速迭代需要更多手工工作 | 用户量大后适合拆实时服务 |
| Java + Spring | 成熟、企业能力完整 | 早期工程和服务器资源较重 | 当前不采用 |
| Python | AI 和脚本方便 | 实时聊天和大型类型契约不是最佳主后端 | 后续用于审核/算法 Worker |

选择 TypeScript 不是因为它“永远最快”，而是方圆里的第一风险是复杂状态写错，不是 CPU 不够。NestJS 的模块、依赖注入、守卫和 WebSocket 能把业务边界落实成代码结构。

### 3.2 使用 Fastify

NestJS 11 官方支持 Fastify 5。使用 Fastify 作为 HTTP 适配器，保留 NestJS 的模块结构，同时减少不必要的 HTTP 开销。

### 3.3 模块化单体

第一版只有一个主要后端代码库，但内部模块不互相直接改表：

```text
identity       账号、设备、资料、隐私
relationships  好友申请、好友设置、黑名单
geo            高德坐标、广场网格、锚点
places         POI、地点群、认证、热度和管理
activities     活动、报名、审批、成员和公告
conversations  会话、消息、已读、未读和搜索
posts          动态、媒体、点赞、评论和分发
notifications  系统会话、推送和免打扰
media          上传凭证、处理状态和过期
governance     举报、证据、审核和审计
```

跨模块业务通过应用服务和可靠事件执行。例如同意好友申请由关系模块负责事务，随后通知会话模块创建私聊，不允许好友页面自己插入会话数据。

---

## 4. 数据访问选择

### 4.1 不把 ORM 当作数据库设计者

PostgreSQL、PostGIS、消息序号、部分唯一索引、事务锁和分区是方圆里的关键能力。数据库结构必须以 SQL 迁移为最终事实，不能依赖 ORM 自动同步生产库。

选择：

- `pg`：PostgreSQL 官方协议客户端；
- 统一 `DatabaseService`：全应用共享连接池、生命周期和事务上下文，业务 Repository 不直接创建或关闭连接池；
- Kysely：在统一数据库边界稳定后渐进引入，为常规查询提供 TypeScript 类型安全；
- SQL migration：显式创建表、索引、PostGIS、约束和数据迁移；
- 生产环境禁止 `synchronize=true` 或任何自动改表。

### 4.2 为什么暂不选 Prisma

Prisma 很适合常规业务，但方圆里大量使用 PostGIS、自定义索引、消息分区和原生 SQL。使用 Prisma 可能迫使项目在“方便生成模型”和“绕开空间类型”之间反复折中。

### 4.3 原生 SQL 与 Kysely 的渐进策略

第一批真实业务纵切已经使用参数化原生 SQL。为了避免在业务仍快速变化时一次性重写数据访问层，现阶段先把连接池、查询执行器和事务上下文收口到统一数据库模块。Repository 只能依赖稳定的查询执行接口，不得自行创建 `pg.Pool`。

后续按模块渐进迁移：Kysely 负责常规类型安全查询，复杂锁、批量写入和 PostGIS 查询继续允许使用参数化原生 SQL。数据库迁移始终以 SQL 为最终事实，不能由 Kysely 或其他 ORM 自动同步生产结构。

### 4.4 连接与事务边界

- 一个 API 进程只拥有一个共享 PostgreSQL 连接池，默认上限由 `DATABASE_POOL_MAX` 控制；
- 连接池由数据库基础设施模块创建和关闭，业务模块不参与生命周期管理；
- Repository 通过查询执行接口访问数据库，并可加入应用服务建立的环境事务；
- 嵌套事务调用复用当前事务连接，避免同一业务用例在多个连接上部分提交；
- 事务回调必须等待全部数据库操作完成，禁止在事务中启动不等待完成的后台任务或执行长时间外部网络请求；
- 迁移工具使用独立短连接和 advisory lock，不复用运行时连接池；
- 涉及多个模块的最终一致性通知使用事务发件箱，不依赖提交后的尽力发布。

---

## 5. 正式仓库结构

正式项目建议使用一个单体仓库：

```text
fangyuanli-platform/
├─ apps/
│  ├─ mobile/                 Flutter App
│  ├─ api/                    NestJS HTTP + WebSocket
│  ├─ worker/                 媒体、通知、热度、过期清理任务
│  └─ admin-web/              运营审核后台
├─ packages/
│  ├─ contracts/
│  │  ├─ openapi/
│  │  ├─ asyncapi/
│  │  ├─ generated-ts/
│  │  └─ generated-dart/
│  ├─ config/                 TypeScript 共享配置和枚举
│  ├─ observability/          日志、trace、指标
│  └─ testing/                测试工厂和契约工具
├─ database/
│  ├─ migrations/
│  ├─ seeds/
│  ├─ fixtures/
│  └─ README.md
├─ infra/
│  ├─ docker/
│  ├─ nginx/
│  ├─ staging/
│  └─ production/
├─ docs/
│  ├─ adr/                    技术决策记录
│  ├─ runbooks/               故障处理手册
│  └─ product/
├─ scripts/
├─ .env.example
├─ pnpm-workspace.yaml
└─ README.md
```

### 5.1 为什么同一个仓库

- API 契约修改能同时更新后端和 Flutter 客户端；
- 一次提交可以包含数据库迁移、接口和界面适配；
- 早期团队不需要维护多个仓库权限和发布流程；
- 后续真正拆服务时再拆，不提前承担成本。

### 5.2 不把原型代码直接复制进正式 App

当前 HTML 原型是产品验证资料。正式 Flutter 页面会参照它重建，但不会把不断叠加的原型 JavaScript 直接转换成生产代码。保留原型作为交互参照，避免把演示状态带入真实业务。

---

## 6. Flutter 工程结构

Flutter 按功能模块组织：

```text
apps/mobile/lib/
├─ app/
│  ├─ router/
│  ├─ theme/
│  └─ bootstrap/
├─ core/
│  ├─ api/
│  ├─ realtime/
│  ├─ storage/
│  ├─ permissions/
│  ├─ media/
│  └─ widgets/
├─ features/
│  ├─ auth/
│  ├─ plaza/
│  ├─ places/
│  ├─ activities/
│  ├─ posts/
│  ├─ friends/
│  ├─ chat/
│  └─ profile/
└─ generated/
   └─ contracts/
```

关键规则：

- 页面不得直接调用底层 HTTP；通过对应 feature repository；
- 所有聊天页面复用同一个 ChatScreen 和输入组件；
- 所有个人头像打开统一 ProfileRoute；
- 所有动态入口打开统一 PostDetailRoute；
- 返回行为由路由栈和来源上下文决定；
- Token 进入 Keychain/安全存储；
- 草稿、表情和最近页面可保存本地，服务端事实不得只保存在本地；
- API DTO 由契约生成或严格映射，不在多个功能模块复制。

状态管理库在创建 Flutter 工程时二选一后锁定，建议 Riverpod；不得同时混用多套全局状态框架。

---

## 7. 后端工程结构

```text
apps/api/src/
├─ main.ts
├─ app.module.ts
├─ common/
│  ├─ auth/
│  ├─ errors/
│  ├─ idempotency/
│  ├─ pagination/
│  ├─ validation/
│  └─ observability/
├─ modules/
│  ├─ identity/
│  ├─ relationships/
│  ├─ geo/
│  ├─ places/
│  ├─ activities/
│  ├─ conversations/
│  ├─ posts/
│  ├─ notifications/
│  ├─ media/
│  └─ governance/
└─ infrastructure/
   ├─ database/
   ├─ redis/
   ├─ cos/
   ├─ amap/
   └─ push/
```

每个业务模块内部：

```text
module/
├─ api/             controller、DTO、WebSocket handler
├─ application/     用例和事务边界
├─ domain/          状态、规则、枚举
├─ infrastructure/  repository 和外部服务实现
└─ tests/
```

这不是为了增加文件数量，而是保证规则只存在一个地方。例如“已有 8 人时不能把上限改为 7”在活动 domain 中验证，创建接口和管理接口共同调用。

---

## 8. 实时聊天实现

### 8.1 第一版

- API 和 WebSocket 使用同一 NestJS 工程、不同接入处理器；
- 消息写入 PostgreSQL 后才返回 `message.accepted`；
- Redis 用于在线连接映射、短期输入状态、跨进程发布订阅和未读缓存；
- PostgreSQL 的消息序号和已读游标是最终事实；
- HTTP 发送是 WebSocket 弱网兜底，两者调用同一应用服务；
- Worker 处理系统推送、过期和非实时工作。

### 8.2 什么时候拆聊天服务

只有满足以下任意情况才拆：

- API 与 WebSocket 的扩容节奏明显不同；
- 单进程连接数或消息吞吐成为瓶颈；
- 聊天发布影响普通 API 延迟；
- 有独立实时团队维护；
- 压测和监控证明拆分收益大于复杂度。

不能只因为“社交 App 应该用微服务”就提前拆。

---

## 9. 搜索与队列

### 9.1 搜索

MVP 使用 PostgreSQL：

- 规范化关键词；
- `pg_trgm` 或目标版本支持的中文搜索方案；
- 不同类别单独查询和评分；
- 消息按保存期和权限过滤；
- 搜索接口每类最多展示 3 条。

当数据库搜索影响写入或需要拼音、同义词、复杂召回时，再增加 OpenSearch/Elasticsearch。

### 9.2 后台任务

第一版使用 Redis 队列，任务包括：

- 图片缩略和方向修正；
- 视频 20 秒校验、转码和封面；
- APNs 推送；
- 地点热度定时计算；
- 消息与媒体过期；
- 活动开始、结束和期待匹配；
- 举报安全检测；
- 搜索索引刷新。

每个任务必须：

- 有唯一任务键；
- 可重复执行而不产生重复结果；
- 有最大重试、退避和死信记录；
- 带 `traceId`；
- 不在 API 请求内长时间阻塞。

---

## 10. 环境划分

| 环境 | 用途 | 数据 |
|---|---|---|
| `dev` | 开发者功能调试 | 虚构数据 |
| `staging` | 董事长验收、多账号和真机测试 | 专用测试账号，不含生产数据 |
| `production` | 正式用户 | 真实数据 |

规则：

- 三套环境的数据库、Redis、COS、短信和推送证书完全隔离；
- staging 可以在单台 CVM 上用容器运行 PostgreSQL/PostGIS 和 Redis，以节省早期费用；
- production 使用腾讯云托管 PostgreSQL 和 Redis；
- 任何人不得把生产备份下载到普通开发电脑；
- 测试账号和正式账号不能互通。

---

## 11. 测试策略

### 11.1 测试层级

| 层级 | 验证 |
|---|---|
| 单元测试 | 活动人数、拉黑恢复、热度衰减、广场排序等规则 |
| 数据库集成测试 | 事务、锁、唯一约束、PostGIS、消息序号 |
| API 契约测试 | OpenAPI 请求、响应和错误码 |
| WebSocket 测试 | 确认、去重、断线、补拉、未读同步 |
| Flutter 组件测试 | 动态图片、评论、输入框、红灰点 |
| 双账号端到端 | 好友、拉黑、活动审批、私聊、动态通知 |
| iPhone 真机 | 定位、锚点、相机、麦克风、推送、后台恢复 |
| 弱网测试 | 丢包、断网、重复请求、消息顺序 |

### 11.2 第一条纵向链路

正式编码不按“先写完全部后端，再写全部 App”推进。第一条链路选择：

```text
短信测试登录
  → 两个测试账号
  → A 申请 B
  → B 同意
  → 双方联系人出现
  → 建立私聊
  → 收发文字
  → 已读和红点同步
  → 拉黑、发送失败、解除恢复
```

它会同时验证账号、关系、会话、实时、数据库、Flutter 和多设备同步，是最适合作为工程地基的第一条链路。

---

## 12. 代码质量规则

- TypeScript 开启严格模式；
- 禁止生产代码使用无说明的 `any`；
- 所有写接口必须有鉴权、幂等和审计判定；
- 所有数据库查询参数化；
- 所有数据库结构变化必须是可回滚或有恢复方案的迁移；
- 所有枚举变更先更新 API 契约；
- 日志不得记录 Token、验证码、完整手机号、身份证件或精准位置；
- 依赖版本由锁文件固定；
- 生产镜像使用固定版本和不可变标签；
- 合并前运行格式、静态检查、单元测试、契约检查和迁移检查；
- 不允许直接在生产数据库手工改表；
- 功能开关和后台参数有默认值、版本和审计。

---

## 13. 决策记录

| 编号 | 决策 | 状态 |
|---|---|---|
| ADR-001 | Flutter 作为正式移动端 | 已决定 |
| ADR-002 | TypeScript + NestJS 11 + Fastify | 已决定 |
| ADR-003 | Node.js 24 LTS | 已决定 |
| ADR-004 | PostgreSQL 18 + PostGIS；购买前验证插件 | 已决定/待环境验证 |
| ADR-005 | Kysely + pg + SQL migration | 已决定 |
| ADR-006 | 模块化单体，暂不拆微服务 | 已决定 |
| ADR-007 | Redis 7.x 标准架构起步 | 已决定 |
| ADR-008 | COS 私有桶和预签名媒体流 | 已决定 |
| ADR-009 | iOS 最终构建使用 Mac/Xcode | 平台硬性要求 |
| ADR-010 | 第一条纵向链路为好友 + 私聊 | 已决定 |

---

## 14. 下一步

在正式工程创建前，需要董事长准备腾讯云服务器和基础账号信息。具体购买与安全清单见：

`方圆里-MVP-v1.0-腾讯云准备清单-v0.1.md`

服务器准备好以后，下一阶段才执行：

1. 初始化正式 Git 仓库；
2. 创建 Node/NestJS、Flutter、Worker 和后台工程；
3. 配置 staging Docker 环境；
4. 建立 PostgreSQL/PostGIS 第一批迁移；
5. 导入 OpenAPI/AsyncAPI；
6. 开发第一条好友 + 私聊纵向链路；
7. 在 iPhone 上完成第一次真实安装和双账号测试。
