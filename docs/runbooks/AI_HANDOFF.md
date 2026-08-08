# 方圆里 AI 与开发交接指南

更新时间：2026-08-04

这份文件用于以下场景：

- ChatGPT/Codex 重装或更换设备；
- 新的 AI 任务接手开发；
- 新开发者加入项目；
- 需要快速恢复当前项目背景、工程状态和下一步工作。

## 1. 项目一句话

方圆里是一款以现实位置为入口的本地社交 App：位置让陌生人相遇，好友让关系离开位置后继续存在。

项目负责人是用户本人（产品决策者）；Codex 承担产品经理、技术负责人和主要开发协作者。遇到未定产品规则时先提出选项和影响，由用户决定，不要擅自把待定内容写死。

## 2. 仓库与权威资料

GitHub 私有仓库：

```text
make853/fangyuanli-platform
```

本机常用路径：

```text
/Users/lightcat/Documents/Codex/fangyuanli-platform
```

资料优先级：

1. 产品行为：`docs/product/PRODUCT_SPEC.md`
2. 决策入口：`docs/product/DECISION_REGISTER.md`
3. 当前工程状态：`docs/runbooks/PROJECT_STATUS.md`
4. 平台公共能力与所有权：`docs/architecture/PLATFORM_CAPABILITY_MAP.md`
5. 技术方案：`docs/architecture/TECHNICAL_PLAN.md`
6. 数据与系统架构：`docs/architecture/DATA_AND_SYSTEM_ARCHITECTURE.md`
7. HTTP API：`packages/contracts/openapi-v1.yaml`
8. 实时事件：`packages/contracts/asyncapi-v1.yaml`
9. 数据模型：`database/model.dbml`
10. 工程协作约束：`AGENTS.md`
11. 部署说明：`docs/runbooks/DEPLOYMENT.md`

视觉与交互基线：

- `docs/baselines/方圆里-iPhone原型-v0.73.html`
- `docs/baselines/方圆里-MVP-v1.0-产品规格书.docx`

当原型、旧聊天总结和正式规格冲突时，以 `PRODUCT_SPEC.md` 和用户最新明确决定为准。当前 Flutter App 是视觉基线；原型 v0.73 主要作为交互习惯、页面路径和状态反馈参考，不代表真实后端已经实现，也不得直接复制其 HTML/CSS/JavaScript 实现。

## 3. 当前工程状态

已经完成：

- iPhone 原型 v0.73 冻结；
- MVP 产品规格、技术方案、API 契约、实时事件契约和 DBML 数据模型；
- pnpm monorepo 骨架；
- NestJS + Fastify API 健康检查；
- PostgreSQL + PostGIS、Redis 的 Docker Compose 基础配置；
- 基础结构检查、API 测试、TypeScript 编译和 GitHub CI；
- GitHub 私有仓库建立；
- 手机号登录、设备会话和服务端令牌校验；
- A/B 测试账号；
- 好友申请、同意/拒绝、联系人、单向设置、删除好友；
- 拉黑、解除拉黑及原好友关系恢复；
- 每对好友唯一私聊会话；
- 私聊文字消息、服务端顺序和客户端幂等；
- 消息分页、首条未读定位、已读游标和导航未读汇总；
- 拉黑后的发送硬拦截与解除后的恢复；
- staging A/B 双账号消息并发、重试、未读和已读闭环验收；
- WebSocket访问令牌鉴权、心跳和服务端会话复核；
- Redis Streams事件游标、断线回放和REST增量同步；
- 同一账号多连接实时消息与已读状态同步；
- staging A/B实时验收覆盖未鉴权拒绝、多连接、幂等、断线恢复、REST补偿和拉黑拦截；
- staging 部署和真实 A/B 关系闭环验收；
- 编译产物启动检查已纳入 CI。
- Flutter iPhone 工程、环境、主题与五栏基础导航；
- Flutter 手机号登录、令牌安全存储、刷新与设备会话；
- Flutter 好友消息入口、好友申请同意/拒绝和联系人同步首版；
- 好友申请处理后保留状态且不会自动发送寒暄消息；
- Flutter 好友资料与关系设置：备注、动态权限、置顶、删除好友和加入黑名单；
- Flutter 账号与安全、黑名单列表和解除拉黑后的原关系恢复；
- Flutter 好友申请、资料设置和黑名单恢复的模型、状态控制器和页面关键路径测试；
- Flutter 私聊历史、实时收发、会话未读和前后台恢复；
- 服务端个人资料读取、版本化更新、隐私设置及好友/陌生人/拉黑关系裁剪；
- Flutter 本人资料、编辑资料、隐私设置和真实好友资料读取；
- staging A/B 个人资料权限与状态恢复验收。
- 服务端媒体上传会话、COS短期直传凭证、完成确认、幂等重试和对象存在性校验；
- 媒体上传与处理状态SQL迁移、腾讯云COS适配层和服务端核心规则自动化测试。
- Flutter 系统选图、图片压缩与SHA-256、COS直传、稳定幂等键、断网续传和任务跨启动恢复底座；
- iOS相册/相机权限说明以及正常上传、断网、过期凭证、文件丢失和恢复任务自动化测试。
- 全局共享数据库连接池、查询执行接口和可嵌套事务上下文，五个现有 Repository 已移除独立连接池；
- 真实 PostGIS 迁移/事务 CI 以及 Flutter 静态分析/测试 CI 已配置；
- 数据访问架构决策已记录，Kysely 在统一数据库边界内渐进引入。
- Flutter 共享鉴权客户端已成为好友、会话、资料、实时补偿和媒体模块的统一网络入口；会话加载只在 App 根组合层注入；
- 持久化媒体任务带不可变 `ownerUserId`，账号切换会阻断原账号延迟请求，App 重启只恢复当前账号任务；旧版无归属任务不自动迁移；
- 移动端网络与账号任务边界已记录在 `docs/architecture/decisions/0002-mobile-authenticated-client-and-account-scoped-tasks.md`。
- 鉴权冷启动已改为本地优先：有效刷新凭证会立即恢复账号，不在启动页等待15分钟访问令牌续期；断网、超时、限流和服务端暂时故障不会误删本地登录，只有刷新凭证过期或被明确拒绝才退出。
- COS 正式环境使用绑定 CVM 的专用 CAM 角色和自动轮换临时凭证，长期 SecretKey 只允许本地开发兼容；该决定记录在 `docs/architecture/decisions/0003-cos-cvm-role-credentials.md`；
- COS 最小权限策略模板位于 `docs/security/tencent-cos-staging-policy.template.json`，部署后运行 `pnpm --filter @fangyuanli/api check:cos` 验证一次性 PUT、HEAD 和 DELETE。
- staging 私有 COS、最小权限 CAM 角色和 CVM 实例角色已完成配置，真实 iPhone 模拟器上传验收已覆盖 iOS 压缩、COS 直传、上传中断后续传和过期凭证换新；测试入口位于 `apps/mobile/integration_test/media_upload_staging_test.dart`，不进入正式 App。
- 图片处理 Worker、头像/背景墙绑定、签名读取和旧媒体延迟清理已完成；Flutter 已通过可替换的裁剪端口接入 1:1 头像裁剪，背景墙不强制裁剪；
- 高频用户身份资料已从完整个人资料中分层：好友申请、联系人、会话和消息返回头像与资料版本；Flutter以媒体ID缓存头像并监听 `profile.updated` 静默刷新；架构决定见 `docs/architecture/decisions/0004-versioned-user-identity-projections.md`；
- Flutter 已建立统一的本地 SQLite 数据库边界，完整资料按当前登录账号持久化并采用本地优先、后台静默刷新；缓存版本、故障降级和后续本地消息扩展规则记录在 `docs/architecture/decisions/0005-mobile-local-first-profile-snapshots.md`；
- 私聊消息最初通过 SQLite 版本2落地，现已由版本4原位迁移为统一会话消息表：按账号与会话隔离、消息ID幂等、会话序号唯一；聊天页本地优先并通过 `afterSequence` 多页增量补拉，发送成功和实时消息都会写回本地。iPhone `profile` 模式已通过彻底退出后的冷启动无闪屏和飞行模式读取本地消息验收；离线期间产生新消息后的恢复增量补拉仍待人工验收。设计边界见 `docs/architecture/decisions/0006-mobile-local-message-snapshots-and-sequence-sync.md`；
- 真机验收曾发现联系人列表仍依赖网络，Bb 会在冷启动先缺失再出现；数据库版本3已增加账号概览快照，好友申请、联系人、黑名单、会话列表和未读数改为本地先显示、后台静默更新，成功的备注/置顶/拉黑等本地投影立即持久化。账号隔离与冷启动自动化测试、真机彻底退出重开、飞行模式读取和恢复联网静默刷新现已全部通过。设计边界见 `docs/architecture/decisions/0007-mobile-account-overview-snapshots.md`；
- 私聊缓存验收结论已推广为全部聊天的统一约束：广场、地点、活动、私聊和系统会话共用 `ConversationMessage`、统一 SQLite 消息表和 `ConversationSyncController`，复用序号同步、实时合并、未读与未来 outbox；各业务模块只提供位置、角色、禁言、状态和读写能力策略，不得复制缓存。旧 `DirectMessage` 数据已由数据库版本4原位迁移，见 `docs/architecture/decisions/0008-unified-conversation-cache-and-sync-engine.md`；
- 统一文字消息 outbox 已落地：SQLite v5 将待确认和失败消息与服务器历史分表保存；点击发送先本地乐观显示，HTTP/实时确认按稳定 `clientMessageId` 原位替换，失败显示红色感叹号并复用同一键重试。场景短期凭证由统一发送器通过可替换 resolver 获取；广场位置令牌缺失或过期时静默刷新一次并复用原幂等键，禁止为刷新凭证重复造消息。进程内同步快照避免返回前台先空白再闪现；长聊天完成底部定位后再显示，键盘开合只做时间线底部锚点修正，同一乐观消息确认时不重复滚动。会话 provider 只由稳定 `conversationId` 标识，位置令牌刷新不得重建聊天和头像。见 `docs/architecture/decisions/0017-durable-conversation-outbox-and-optimistic-send.md`；
- staging 验收增加稳定门：`BUILD_IDENTITY` 由 Git 提交和工作区指纹生成，并在“我的 → 关于方圆里”连同 A/B 角色展示；受版本控制的 iOS 启动入口只接受精确设备 ID，强制 A=真机、B=模拟器，禁止以设备名称或同一目标做联调。SSH 转发由幂等后台脚本独立于 Flutter 生命周期维护，关闭 Xcode 或 Flutter 终端不得再导致 App 误报服务器不可用。任何聊天体验结论前先核对两端构建身份完全一致；
- 统一聊天输入区域由 `ChatComposerSurface` 状态机和单一底部占位控制，系统键盘、表情、附件和语音不得在业务页面分别实现。2026-08-04 已在 iPhone 16 Pro 的 staging Profile 构建完成冷启动真机验收：键盘与表情切换无尾帧抖动，表情面板开合动画统一，连续发送表情不唤起系统键盘，最后消息、顶栏和底栏均稳定。该结果是广场、地点、活动与好友私聊的冻结交互基线，见 ADR 0018；
- 广场已成为统一会话底座的第二个真实适配器并部署到 staging：短期位置令牌绑定当次四广场ID，当前区域可发言，历史进入离开后只读；一年文字保留、精确首条未读、红灰免打扰、导航隔离、实时合并和账户级本地缓存均已接入。2026-08-04 已完成 A/B 真接口与体验验收：锚点稳定切换、同广场实时收发、未读与已读清零、灰色免打扰、跨账号位置令牌拒绝、真机断开 USB 后的真实离线补拉、失败消息幂等重试以及离开区域只读均通过；通用聊天只读表面可直接复制到地点和活动；
- 广场采用单层权威区域：首版是2公里正方形，未来通过完整地图版本演进为无重叠、无空缺的不规则多边形，不建立第二套业务广场。命名策略 v6 要求最终高德 POI 坐标严格位于所属区域内部，保存供应商、POI标识和坐标审计；格外候选不得借名，无格内候选退回中性编号。见 `docs/architecture/decisions/0016-single-layer-versioned-plaza-regions.md`；
- staging 媒体验收已扩展为 A/B 双账号，覆盖好友完整资料、拉黑后最小头像资料、背景墙隔离和测试状态恢复；原生裁剪手势仍需在 iPhone 模拟器或真机人工确认一次。

好友关系、私聊文字消息、实时推送、断线补偿、多连接同步、个人资料和资料图片已经通过真实服务器 A/B 闭环；Flutter 已完成登录、好友申请、联系人、关系设置、私聊实时收发、资料编辑，以及头像/背景墙的可恢复上传、处理、绑定和权限读取。个人历史动态与聊天媒体仍待后续接入。HTML 原型中的其余交互大部分仍是模拟状态。

## 4. 下一条开发主线

不要同时铺开全部功能。第一条真实业务纵切固定为：

```text
账号登录
→ A/B 测试账号
→ 好友申请
→ 同意或拒绝
→ 联系人同步
→ 私聊
→ 未读游标
→ 拉黑
→ 解除拉黑并恢复正确关系
```

建议实施顺序：

好友关系、私聊文字消息、分页、未读游标、拉黑拦截、实时通道、断线补偿、多连接同步、个人资料与资料媒体闭环已经完成；四广场真机审计也已通过，广场会话纵切已部署并完成 A/B 真接口收发与未读闭环。接下来固定按以下顺序继续：

1. 完成首条未读提示、搜索锚点表面和真机长聊天验收；公共控制器已接入 `beforeSequence`、`afterSequence` 与连续 `anchorSequence` 窗口；
2. 接入真实广场通知设置和历史进入，再开始地点会话策略；
3. 将广场已验收的只读能力作为地点和活动的公共场景策略，不复制缓存、输入或发送状态机；
4. 接入个人历史动态并复用现有资料可见性；
5. 聊天图片、语音和视频复用现有媒体上传、处理、签名读取和清理基础设施，并扩展已经落地的账号隔离统一 outbox，不另建媒体发送队列。

## 5. 工程原则

- 保持模块化单体，不在 MVP 阶段拆微服务。
- 服务器端是权限与数据的权威来源，客户端隐藏按钮不能代替鉴权。
- 所有写请求必须考虑幂等，消息必须具有服务端顺序。
- 数据库变更必须使用 SQL 迁移，禁止依赖生产自动同步。
- 每个功能必须同时验证 A/B 双账号、返回路径、未读状态和异常恢复。
- `main` 必须始终可测试、可部署、可回滚。
- 服务器不直接手工修改源码；使用 Git 提交和可回滚部署。
- 不提交 `.env`、密钥、证书、用户媒体、生产数据或真实个人信息。

## 6. 本地验证

环境：

- Node.js 24 LTS
- pnpm 11
- Docker / Docker Compose
- Flutter 稳定版（开始正式客户端开发时安装）

常用命令：

```bash
pnpm install
pnpm verify
pnpm test
pnpm --filter @fangyuanli/api build
pnpm --filter @fangyuanli/api smoke:prod
docker compose up -d postgres redis
pnpm --filter @fangyuanli/api dev
```

API 健康检查：

```text
GET http://localhost:3000/health
```

开始修改前执行：

```bash
git status -sb
git pull --ff-only
```

修改后至少执行：

```bash
pnpm verify
pnpm test
```

## 7. Git 工作方式

- 默认从 `main` 创建 `agent/*` 或 `feature/*` 分支。
- 只提交本次任务相关文件。
- 提交前检查 `git diff --check`、测试和构建。
- 推送分支后通过 PR 合并，保留清晰变更说明。
- 若 Codex 的 GitHub 插件暂时不可用，可使用本地 `git` 与 `gh`，不影响开发。

## 8. 服务器与部署

当前只使用 staging，生产环境尚未启用。服务器最终承载 API、数据库、Redis、媒体处理和部署服务，本地电脑关机不应影响已部署系统。

四广场边界或命名问题使用 `docs/runbooks/PLAZA_REGION_AUDIT.md` 的非生产审计工具复现，不得为了调试在正式 App 或公开接口返回精确位置、网格索引和 POI 坐标。

部署原则详见 `docs/runbooks/DEPLOYMENT.md`。任何 AI 或开发者都不得把服务器 IP、SSH 私钥或环境密钥写入仓库。部署信息通过安全的环境变量、腾讯云控制台或受控密钥管理传递。

## 9. 重装或换设备后的恢复步骤

```bash
gh auth login -h github.com -p https -w
git clone https://github.com/make853/fangyuanli-platform.git
cd fangyuanli-platform
pnpm install
pnpm verify
pnpm test
```

然后让新的 AI 按顺序阅读：

1. `AGENTS.md`
2. 本文件
3. `docs/runbooks/PROJECT_STATUS.md`
4. `docs/product/PRODUCT_SPEC.md`
5. 当前任务涉及的架构、契约和代码

建议交接提示词：

> 你现在接手方圆里项目。请先阅读 AGENTS.md、docs/runbooks/AI_HANDOFF.md、docs/runbooks/PROJECT_STATUS.md 和 docs/product/PRODUCT_SPEC.md。不要立即大范围改代码。先检查 git 状态、运行现有验证，并汇报当前阶段、下一条最小业务纵切、风险和实施计划。所有实现必须覆盖 A/B 双账号、服务端权限、持久化、未读状态、返回路径和异常恢复。

## 10. 当前已知非代码问题

- Codex 桌面端的 GitHub 插件曾出现图标加载缓慢、工具不可用；ChatGPT 网页端可以访问同一仓库。该问题不应阻塞开发，可使用本地 Git/`gh` 作为可靠后备。
- VPN/代理可能影响 SSH、插件目录和外部连接。遇到问题时先区分：本机网络、Codex 沙盒、GitHub 授权、腾讯云安全组和服务器服务，不要把它们混成一个故障。
- Codex 受限任务内运行 `flutter build ios --simulator` 时可能无法连接 CoreSimulator 或执行 SwiftPM 的 `sandbox-exec`；若 Flutter analyze 与测试通过但只出现此类权限错误，应从本机 Terminal/Xcode 复验，不要误判为业务代码故障。

## 11. 接手后的第一份汇报

新 AI 接手后应向用户汇报：

1. 当前仓库分支和工作区是否干净；
2. 最近提交和 CI/测试状态；
3. 当前第一优先级是否仍为 A/B 好友与私聊纵切；
4. 本次准备修改哪些文件；
5. 如何验证，以及哪些步骤需要用户在 iPhone 或第二账号上配合。
