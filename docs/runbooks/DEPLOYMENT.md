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
pnpm db:migrate
sudo install -m 0644 deploy/systemd/fangyuanli-api.service \
  /etc/systemd/system/fangyuanli-api.service
sudo install -m 0644 deploy/systemd/fangyuanli-worker.service \
  /etc/systemd/system/fangyuanli-worker.service
sudo systemctl daemon-reload
sudo systemctl enable fangyuanli-api.service fangyuanli-worker.service
sudo systemctl restart fangyuanli-api.service fangyuanli-worker.service
curl --fail --retry 15 --retry-connrefused --retry-delay 1 --max-time 5 \
  http://127.0.0.1:3000/health
```

systemd 重启后 Node 进程通常需要不足一秒开始监听；健康检查必须允许这段
启动窗口，但重试结束仍失败时部署应立即停止并查看服务日志。

查看运行状态和最近日志：

```bash
systemctl status fangyuanli-api.service --no-pager
journalctl -u fangyuanli-api.service -n 100 --no-pager
systemctl status fangyuanli-worker.service --no-pager
journalctl -u fangyuanli-worker.service -n 100 --no-pager
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

角色只授予指定私有桶 `temporary/*` 和 `processed/*` 前缀所需的
`PutObject`、`GetObject`、`HeadObject` 和 `DeleteObject`。其中客户端仍只会
获得 `temporary/*` 单对象 PUT 地址；GET 和派生图写入只由服务端 API/Worker
使用。策略模板见
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

## 位置上下文密钥

地点、广场、活动和附近动态不会在每个业务请求里重复携带明文经纬度，
而是使用绑定账号的短期加密位置令牌。每个环境必须单独生成32字节随机密钥，
只写入受控环境文件：

```bash
openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n'
```

将结果保存为 `FANGYUANLI_LOCATION_CONTEXT_KEY`，不得提交到Git，也不得在
staging和production之间共用。轮换密钥会使现有短期位置令牌立即失效，因此
应在低峰期轮换，并允许客户端自动刷新 `/geo/context`。

广场稳定策略可以通过环境变量调节，不需要重新发布 App。未配置时使用
MVP 默认值：

```text
PLAZA_ANCHOR_RADIUS_METERS=150
PLAZA_MAXIMUM_ACCURACY_METERS=80
PLAZA_SWITCH_CONFIRMATION_COUNT=3
PLAZA_SWITCH_DWELL_SECONDS=60
LOCATION_CONTEXT_TTL_SECONDS=600
```

这些参数只改变锚点判断，不改变网格 ID。网格边长和投影属于版本化数据库
配置，禁止直接修改已激活版本；调整时必须新增网格版本并设计灰度迁移。
