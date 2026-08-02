# 四广场地理审计

该工具用于 staging 和本地开发环境，核对用户锚点、四个方格以及自动命名地标
之间的空间关系。它不属于正式 App 功能，也不提供生产 HTTP 接口。

## 适用场景

- 验证四个广场是否确实来自同一组相邻方格；
- 验证自动命名地标是否位于自己的方格内部；
- 排查名称方向与现实地图不一致的问题；
- 调整网格版本或未来多边形边界后执行回归验收。

## 在 staging 生成

先让测试手机刷新一次位置；由于自动命名不阻塞 `/geo/context`，若刚升级命名
策略，可以等待数秒后再刷新一次。然后在服务器仓库运行：

```bash
NODE_ENV=staging pnpm --filter @fangyuanli/api audit:plazas -- \
  --latest \
  --output /tmp/fangyuanli-plaza-audit.svg
```

明确知道测试账号 UUID 时，使用：

```bash
NODE_ENV=staging pnpm --filter @fangyuanli/api audit:plazas -- \
  --user-id TEST_USER_UUID \
  --output /tmp/fangyuanli-plaza-audit.svg
```

工具要求恰好四个不同方格，使用正式 `PlazaGridProjector` 完成边界和包含关系
计算。输出结果为 `PASS` 时，所有带坐标的命名地标都属于自己的方格；中性编号
没有地标坐标，不会被误判为失败。

## 隐私与清理

- 工具在 `NODE_ENV=production` 下强制拒绝运行；
- SVG 不显示账号、广场 UUID、网格索引或精确经纬度；
- 输出文件权限固定为 `0600`；
- SVG 只用于本次开发验收，不得提交 Git 或发送给无关人员；
- 验收结束后删除服务器和本地临时文件。

## 判断标准

1. 四个方格应组成围绕用户所在角点的连续 2×2 组合；
2. 主广场包含用户锚点；
3. 每个绿色地标点位于自己卡片对应的方格内；
4. 任一红色点代表历史跨格命名或数据异常，禁止进入发布；
5. 修改展示名或边界版本不得改变广场 ID、会话 ID 或历史消息。
