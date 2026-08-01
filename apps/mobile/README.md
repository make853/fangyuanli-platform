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

### staging 媒体上传验收

`integration_test/media_upload_staging_test.dart` 不进入正式 App。它会在 iOS
模拟器内生成一张大图，复用产品代码完成压缩、短期凭证申请、COS 直传、完成确认
和媒体状态查询；同一次验收还会模拟上传中断后续传，以及过期凭证自动换新，
用来验证移动端到 staging 的真实上传与恢复链路。

先把 staging API 安全转发到本机 `127.0.0.1:3000`，再在本机终端执行：

```bash
flutter test integration_test/media_upload_staging_test.dart \
  -d "iPhone 16e" \
  --dart-define=API_BASE_URL=http://127.0.0.1:3000 \
  --dart-define=STAGING_TEST_PHONE="$STAGING_TEST_PHONE" \
  --dart-define=STAGING_TEST_CODE="$STAGING_TEST_CODE"
```

测试号码和验证码只通过本机环境变量传入，不写入源码、测试报告或 Git。
