# 方圆里 AI 与开发交接指南

更新时间：2026-07-29

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
2. 当前工程状态：`docs/runbooks/PROJECT_STATUS.md`
3. 技术方案：`docs/architecture/TECHNICAL_PLAN.md`
4. 数据与系统架构：`docs/architecture/DATA_AND_SYSTEM_ARCHITECTURE.md`
5. HTTP API：`packages/contracts/openapi-v1.yaml`
6. 实时事件：`packages/contracts/asyncapi-v1.yaml`
7. 数据模型：`database/model.dbml`
8. 工程协作约束：`AGENTS.md`
9. 部署说明：`docs/runbooks/DEPLOYMENT.md`

视觉与文档基线：

- `docs/baselines/方圆里-iPhone原型-v0.73.html`
- `docs/baselines/方圆里-MVP-v1.0-产品规格书.docx`

当原型、旧聊天总结和正式规格冲突时，以 `PRODUCT_SPEC.md` 和用户最新明确决定为准。原型 v0.73 主要作为视觉与交互习惯参考，不代表真实后端已经实现。

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
- staging 部署和真实 A/B 关系闭环验收；
- 编译产物启动检查已纳入 CI。

好友关系和私聊文字消息已经通过真实服务器 A/B 闭环；实时推送、多设备同步、媒体消息和 Flutter 客户端尚未完成。HTML 原型中的其余交互大部分仍是模拟状态。

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

好友关系、私聊文字消息、分页、未读游标和拉黑拦截已经完成。接下来固定按以下顺序继续：

1. 增加带访问令牌鉴权的私聊实时消息通道；
2. 用现有服务端序号实现断线重连、增量补取和实时去重；
3. 实现多设备已读游标与未读同步；
4. 增加实时通道的 A/B 并发、重连、拉黑和服务器重启测试；
5. 部署到 staging 并进行两台设备/两个账号验收；
6. 再接入 Flutter iPhone 客户端的真实登录、好友和私聊页面；
7. 媒体上传、语音和视频在文字链路稳定后单独实施。

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

## 11. 接手后的第一份汇报

新 AI 接手后应向用户汇报：

1. 当前仓库分支和工作区是否干净；
2. 最近提交和 CI/测试状态；
3. 当前第一优先级是否仍为 A/B 好友与私聊纵切；
4. 本次准备修改哪些文件；
5. 如何验证，以及哪些步骤需要用户在 iPhone 或第二账号上配合。
