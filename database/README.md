# 数据库迁移

`database/migrations` 是数据库结构的唯一事实来源。迁移文件按文件名顺序执行，
一旦进入共享环境就不得修改；后续结构变化必须新增迁移。

## 执行迁移

确认根目录 `.env` 中存在目标环境的 `DATABASE_URL`，然后运行：

```bash
pnpm db:migrate
```

迁移器会：

- 使用 PostgreSQL advisory lock 防止两个部署同时改表；
- 在 `schema_migrations` 中记录文件名和 SHA-256 校验和；
- 每个迁移独立事务提交；
- 拒绝已执行后又被修改的迁移；
- 没有待执行迁移时安全退出。

## Staging A/B 测试账号

测试种子只包含虚构资料，不包含真实手机号。仅在 staging 或开发环境显式执行：

```bash
ALLOW_TEST_SEED=true pnpm db:seed:ab
```

种子程序在 `NODE_ENV=production` 时始终拒绝运行。重复执行不会创建重复账号。

## 回滚原则

第一版不提供自动向下迁移。共享环境出现问题时优先停止部署、从备份恢复，随后
通过新的前向迁移修正，避免破坏性回滚进一步丢失数据。
