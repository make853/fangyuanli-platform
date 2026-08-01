# 测试环境部署手册

当前目标服务器：`fangyuanli-staging-01`。

## 原则

- 服务器不直接手工修改源代码；
- 只部署通过自动检查的版本；
- 数据库迁移在应用启动前执行；
- 部署失败自动保留上一镜像；
- 生产环境启用前另建独立配置与密钥。

## 待完成

1. 创建腾讯云 TCR 镜像仓库；
2. 配置 GitHub Actions 构建镜像；
3. 配置腾讯云 TAT 执行受控部署脚本；
4. 配置健康检查和回滚；
5. 配置数据库备份到 COS。

## Staging API systemd 服务

当前过渡阶段由 systemd 托管编译后的 API，API 只监听服务器回环地址，
不会直接暴露到公网。部署新提交时：

```bash
cd /srv/fangyuanli
git pull --ff-only
pnpm install --frozen-lockfile
pnpm verify
pnpm test
pnpm build:api
sudo install -m 0644 deploy/systemd/fangyuanli-api.service \
  /etc/systemd/system/fangyuanli-api.service
sudo systemctl daemon-reload
sudo systemctl enable --now fangyuanli-api.service
curl --fail http://127.0.0.1:3000/health
```

查看运行状态和最近日志：

```bash
systemctl status fangyuanli-api.service --no-pager
journalctl -u fangyuanli-api.service -n 100 --no-pager
```

## 媒体上传环境

媒体接口使用私有腾讯云COS桶和短期预签名URL。以下值只写入服务器
`/srv/fangyuanli/.env` 或受控密钥系统，不得提交到Git：

```text
TENCENT_COS_REGION
TENCENT_COS_BUCKET
TENCENT_COS_CVM_ROLE
TENCENT_COS_SECRET_ID
TENCENT_COS_SECRET_KEY
```

Staging 和 production 首选给 CVM 绑定专用 CAM 角色，并只填写
`TENCENT_COS_CVM_ROLE`；应用通过实例元数据取得自动轮换的临时凭证，
不在服务器保存永久 SecretKey。`TENCENT_COS_SECRET_ID/SECRET_KEY` 仅作为
本地开发兼容入口，二者不得与 CVM 角色同时作为正式部署方案。

角色只授予指定私有桶 `temporary/*` 前缀的 `PutObject`、`HeadObject` 和
`DeleteObject`，策略模板见
`docs/security/tencent-cos-staging-policy.template.json`。桶名必须包含腾讯云
APPID 后缀，地域创建后不可修改。iOS/Android 原生直传不受浏览器 CORS
限制；只有未来启用 Flutter Web 直传时，才为确定的 Web 域名增加有限的
`PUT`/`HEAD` CORS，禁止使用 `*` 作为正式来源。

配置完成后在服务器仓库执行：

```bash
pnpm --filter @fangyuanli/api check:cos
```

该检查只在 `temporary/diagnostics/` 写入一个很小的随机对象，依次验证短期
预签名 PUT、HEAD 和 DELETE，并在结束时清理。未配置媒体凭证时，健康检查
仍可运行，但申请媒体上传会返回存储暂不可用，不会退化为公开桶或把文件
写进数据库。
