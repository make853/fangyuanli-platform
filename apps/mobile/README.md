# 方圆里 Flutter App

方圆里正式客户端。当前工程使用 Flutter stable，先支持 iOS 与 Web 调试；Web
只用于快速验证页面和 REST 流程，最终产品以 iPhone 客户端为准。

## 当前范围

第一条开发链路按以下顺序推进：

1. 手机号验证码登录与安全会话；
2. 好友申请与联系人；
3. 私聊、未读、置顶和免打扰；
4. 拉黑、恢复与双账号联调；
5. 广场、地点、活动和动态。

原型 v0.73 是视觉和交互基线，不复制其中的模拟数据逻辑。

## 环境配置

所有环境地址通过 `--dart-define` 注入，禁止写入源码或提交密钥。

```bash
flutter run -d web-server \
  --dart-define=APP_FLAVOR=local \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000 \
  --dart-define=REALTIME_URL=ws://127.0.0.1:3000/ws/v1
```

测试服和正式服分别使用 `staging`、`production`，并替换为对应的 HTTPS/WSS
地址。

## 验证

```bash
flutter analyze
flutter test
flutter build web
```

运行 iPhone 模拟器或真机前，Mac 必须安装完整 Xcode，并完成 iOS 开发环境配置。

真机日常开发默认使用 `debug`，支持热重载，但它需要 Flutter/Xcode 调试通道；彻底退出后直接从 iPhone 桌面重开可能立即结束。验证独立冷启动、本地缓存和弱网展示时使用可独立启动的 `profile` 模式：

```bash
IOS_STAGING_DEVICE=<iPhone device id> \
IOS_STAGING_MODE=profile \
zsh build/run-ios-staging-app.sh
```

`profile` 用于接近正式包的体验验收，`debug` 用于边改边看。不要把 debug 版无法脱离调试器重开误判为业务崩溃。

真机 staging 的 API 地址通过 Mac 的 SSH 隧道访问。冷启动与飞行模式下，本地登录、资料、好友、会话和已缓存消息不依赖隧道；恢复网络后若要继续同步服务器数据，运行脚本的终端和隧道仍需保持可用。正式发布包会直接连接部署域名，不依赖开发者电脑。

### staging 媒体上传验收

`integration_test/media_upload_staging_test.dart` 不进入正式 App。它会在 iOS
模拟器内生成测试图片，复用产品代码完成压缩、短期凭证申请、COS 直传、完成确认、
媒体状态查询和资料绑定；同一次验收还会模拟上传中断后续传、过期凭证自动换新，
并使用 A/B 账号验证好友可见头像与背景墙、拉黑后只保留最小头像资料。

先把 staging API 安全转发到本机 `127.0.0.1:3000`，并通过环境变量提供 A/B
测试账号，再在本机终端执行受版本控制的验收入口：

```bash
zsh scripts/run-ios-media-acceptance.sh
```

默认设备为 `iPhone 17`，可用 `IOS_ACCEPTANCE_DEVICE` 覆盖。测试号码和验证码只通过
本机环境变量传入，不写入源码、测试报告或 Git。开发机上的 `build/` 目录可以保留一层
本地包装脚本，用于建立 SSH 隧道并读取 staging 配置，但核心验收逻辑必须留在
`scripts/run-ios-media-acceptance.sh`。
