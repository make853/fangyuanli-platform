# 方圆里工程协作说明

## 权威资料

- 产品行为：`docs/product/PRODUCT_SPEC.md`
- 产品决策入口：`docs/product/DECISION_REGISTER.md`
- 平台公共能力：`docs/architecture/PLATFORM_CAPABILITY_MAP.md`
- API：`packages/contracts/openapi-v1.yaml`
- 实时事件：`packages/contracts/asyncapi-v1.yaml`
- 数据模型：`database/model.dbml`
- 技术方案：`docs/architecture/TECHNICAL_PLAN.md`
- AI与开发交接：`docs/runbooks/AI_HANDOFF.md`

冲突时先报告，不要自行猜测或让实现悄悄偏离规格。

## 工作方式

1. 只读取当前模块需要的文件，避免无关全仓扫描。
2. 每个功能同时考虑服务端权限、持久化、A/B双账号和返回路径。
3. 新增或修改行为必须补自动测试。
4. 数据库变更必须新增SQL迁移，禁止生产自动同步。
5. 不提交密钥、证书、`.env`、用户媒体和生产数据。
6. 不在服务器手工编辑源码；通过Git和可回滚部署发布。
7. 保留模块化单体边界，不提前引入微服务。

## 首条开发链路

账号登录 → 好友申请 → 同意/拒绝 → 联系人同步 → 私聊 → 未读 → 拉黑 → 解除拉黑并恢复正确关系。

新 AI 或新开发者接手时，先读取交接指南和项目状态，检查 Git 工作区并运行现有验证，再提出本次最小变更计划。
