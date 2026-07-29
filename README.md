# 方圆里正式工程

方圆里是一款以现实位置为入口的本地社交 App。本仓库承载正式 Flutter 客户端、NestJS 后端、后台任务、运营后台、数据库迁移和部署配置。

## 当前阶段

- 环境：`staging`
- 产品基线：iPhone 原型 v0.73
- 第一条业务纵切：双账号好友申请、私聊、未读、拉黑与恢复
- 生产环境：尚未启用

## 仓库结构

```text
apps/
  mobile/       Flutter iOS / Android 客户端
  api/          NestJS HTTP / WebSocket API
  worker/       异步任务和媒体处理
  admin-web/    平台运营后台
packages/
  contracts/    OpenAPI / AsyncAPI 契约
  config/       共享配置
  observability/日志、指标和追踪
  testing/      测试工具与夹具
database/
  migrations/   SQL 数据库迁移
  seeds/        开发与测试种子数据
  fixtures/     A/B 账号与场景夹具
infra/          Docker、网关与环境配置
docs/           产品、架构、ADR 与运维手册
```

## 开发原则

1. `main` 必须始终可测试、可部署、可回滚。
2. 功能从 `feature/*` 分支开发，通过检查后合并。
3. 数据库结构只能通过 SQL 迁移修改。
4. 客户端权限展示不能代替服务端权限校验。
5. `.env`、证书、Apple、高德和腾讯云密钥不得提交。
6. 规格、OpenAPI、AsyncAPI、数据库和实现必须同步演进。

## 本地准备

- Node.js 24 LTS
- pnpm 11
- Docker / Docker Compose
- Flutter 稳定版（开发手机端时安装）

```bash
pnpm install
pnpm verify
pnpm test
docker compose up -d postgres redis
pnpm --filter @fangyuanli/api dev
```

API 健康检查：`GET http://localhost:3000/health`
