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
