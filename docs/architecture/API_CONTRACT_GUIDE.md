# 方圆里 MVP v1.0 API 契约 v0.1

> 文档状态：前后端契约初稿
> 配套源文件：`api/openapi-v1.yaml`、`api/asyncapi-v1.yaml`
> 对应数据模型：`database/fangyuanli-mvp-v1.dbml`

---

## 0. 契约目标

这份契约不是服务器实现代码，而是 Flutter、后端、WebSocket 和测试共同遵守的规则。它优先解决原型测试中反复出现的跨页面问题：

- 同意好友申请后，双方联系人、资料页和私聊状态必须同时更新；
- 动态在广场、好友动态、个人资料和动态通知里使用同一个动态 ID；
- 所有头像入口使用同一个用户资料接口；
- 广场、地点、活动和私聊使用统一消息模型；
- 红色未读、灰色未读、底部导航数字和“N 条新消息”使用同一服务端游标；
- 拉黑、解除拉黑和好友恢复在双方账号上保持一致；
- 活动创建和管理使用同一套字段与枚举；
- 每个页面返回时回到哪里由 Flutter 路由栈控制，不由后端猜测。

---

## 1. 协议与版本

### 1.1 接入地址

```text
正式环境 REST:      https://api.fangyuanli.example/api/v1
正式环境 WebSocket: wss://realtime.fangyuanli.example/ws/v1
测试环境:           独立域名、数据库、COS 桶和推送配置
```

域名在正式备案和部署时替换。客户端不得把服务器 IP 写死。

### 1.2 数据格式

- HTTP API 使用 HTTPS + JSON。
- WebSocket 使用 UTF-8 JSON 文本帧。
- 字段使用 `lowerCamelCase`。
- ID 使用不可推测的 UUID 字符串。
- 时间使用 RFC 3339 UTC，例如 `2026-07-28T09:20:15.123Z`。
- 距离输入统一使用整数米，时间长度统一使用整数毫秒或明确命名的秒数。
- 金额若未来使用，以整数“分”保存，不使用浮点数。
- 服务端新增未知字段时，旧客户端应忽略，不得崩溃。

### 1.3 版本策略

- 路径主版本为 `/api/v1`、`/ws/v1`。
- 兼容性新增字段不升级主版本。
- 删除字段、改变字段意义或改变默认行为必须升级主版本或提供迁移期。
- 枚举新增值属于可能发生的兼容更新；Flutter 必须提供 `unknown` 兜底展示。

---

## 2. 认证、设备与安全

### 2.1 Access Token

登录成功后返回：

```json
{
  "accessToken": "opaque-or-jwt-token",
  "accessTokenExpiresAt": "2026-07-28T10:00:00Z",
  "refreshToken": "opaque-refresh-token",
  "refreshTokenExpiresAt": "2026-08-27T09:00:00Z",
  "deviceId": "019c..."
}
```

普通请求携带：

```http
Authorization: Bearer <accessToken>
```

Access Token 有效期和 Refresh Token 有效期是后台安全参数，本契约不锁死具体天数。

### 2.2 Refresh Token

- Refresh Token 保存在 iOS Keychain / Android 安全存储，不写入普通本地数据库或日志。
- 刷新成功后服务端轮换 Refresh Token，旧 Token 立即失效或进入极短并发宽限。
- 退出账号撤销当前设备 Refresh Token 和 WebSocket 会话。
- 修改密码、账号高风险或用户主动“退出所有设备”时撤销全部设备 Token。

### 2.3 请求公共头

| Header | 是否必需 | 用途 |
|---|---:|---|
| `Authorization` | 登录接口外必需 | 身份认证 |
| `X-Request-Id` | 推荐 | 全链路问题定位；客户端生成 UUID |
| `X-Device-Id` | 登录后必需 | 多设备管理 |
| `X-App-Version` | 必需 | 灰度、兼容和问题定位 |
| `X-Platform` | 必需 | `ios` / `android` |
| `X-Idempotency-Key` | 所有重要写操作必需 | 防止重复提交 |
| `X-Location-Context` | 地理资格操作按需 | 短期位置上下文，不直接重复传坐标 |

### 2.4 幂等

以下行为必须幂等：

- 同意或拒绝好友申请；
- 拉黑和解除拉黑；
- 创建动态、活动、评论、报名申请；
- 活动审批；
- 管理员任命、禁言、规则修改；
- 消息发送；
- 媒体上传完成确认；
- 删除内容；
- 更新已读游标。

同一个用户、同一种操作和同一个 `X-Idempotency-Key`：

- 请求内容相同：返回第一次结果；
- 请求内容不同：返回 `409 IDEMPOTENCY_CONFLICT`；
- 不得重复创建业务数据。

聊天另外使用 `clientMessageId` 去重。

---

## 3. 统一响应

### 3.1 成功

```json
{
  "data": {},
  "meta": {
    "requestId": "019c...",
    "serverTime": "2026-07-28T09:20:15.123Z"
  }
}
```

列表：

```json
{
  "data": {
    "items": [],
    "nextCursor": "opaque-cursor-or-null",
    "hasMore": false
  },
  "meta": {
    "requestId": "019c...",
    "serverTime": "2026-07-28T09:20:15.123Z"
  }
}
```

### 3.2 错误

```json
{
  "error": {
    "code": "ACTIVITY_CAPACITY_BELOW_MEMBER_COUNT",
    "message": "人数上限不能低于当前已加入人数",
    "details": {
      "currentMemberCount": 8,
      "requestedCapacity": 7
    },
    "requestId": "019c..."
  }
}
```

规则：

- `code` 是 Flutter 判断逻辑的稳定机器码。
- `message` 是可展示中文，但客户端可按机器码提供更自然的本地文案。
- `details` 只提供安全、必要的上下文。
- 生产环境不得返回堆栈、SQL、文件路径、Token 或他人敏感数据。

### 3.3 HTTP 状态

| 状态 | 场景 |
|---:|---|
| 200 | 查询或更新成功 |
| 201 | 创建成功 |
| 202 | 已接受异步处理，例如媒体转码 |
| 204 | 删除或无正文成功 |
| 400 | 字段、枚举、业务组合不合法 |
| 401 | 未登录、Token 失效 |
| 403 | 已登录但无查看、发言或管理权限 |
| 404 | 对象不存在，或为隐私安全故意按不存在处理 |
| 409 | 幂等冲突、版本冲突、重复关系 |
| 410 | 内容已过期或已不可恢复 |
| 413 | 文件或请求过大 |
| 422 | 格式正确但业务条件不满足 |
| 429 | 频率限制 |
| 500 | 服务端未知错误 |
| 503 | 服务暂不可用 |

---

## 4. 游标、排序与刷新

### 4.1 列表游标

所有持续变化的列表使用不透明游标：

```text
GET /friends?limit=30&cursor=<opaque>
```

- 默认 `limit=20`，最大 `limit=50`。
- 客户端不得解析或修改游标。
- `nextCursor=null` 表示没有下一页。
- 列表排序必须稳定，通常由业务时间 + 唯一 ID 组成。

### 4.2 消息序号

消息不用普通列表游标，而使用会话内 `sequence`：

```text
GET /conversations/{id}/messages?beforeSequence=950&limit=30
GET /conversations/{id}/messages?afterSequence=920&limit=30
GET /conversations/{id}/messages?anchorSequence=925&before=20&after=20
```

- `beforeSequence`：向上加载更早消息。
- `afterSequence`：断线后补取更新消息。
- `anchorSequence`：搜索或未读跳转时获取目标消息上下文。
- 三种模式互斥。

### 4.3 动态刷新

- “最新”动态使用 `publishedAt DESC, postId DESC` 稳定排序。
- 选择具体日期时，只返回该本地日期范围内内容，仍按新到旧排序。
- 下拉刷新携带当前首条动态的更新时间或刷新令牌，获得刚发布内容。
- “热门”不受日期排序限制，但返回热度计算版本和生成时间。

---

## 5. 位置上下文

### 5.1 为什么使用位置令牌

用户打开需要地理能力的页面时，仅向 `/geo/context` 提交当前高德定位。服务端返回短期有效、不可推测的 `locationContextToken`。后续接口使用这个令牌：

- 降低精准经纬度在 URL、日志和各模块重复出现；
- 保证广场、地点、活动和动态使用同一时刻的位置判断；
- 服务端统一处理定位精度、过期和异常移动；
- 不把其他用户位置返回给客户端。

### 5.2 创建或刷新上下文

```http
POST /geo/context
```

请求：

```json
{
  "coordinateSystem": "gcj02",
  "longitude": 113.264385,
  "latitude": 23.129112,
  "accuracyMeters": 18,
  "capturedAt": "2026-07-28T09:20:00Z",
  "motionState": "walking"
}
```

响应：

```json
{
  "data": {
    "locationContextToken": "locctx_opaque",
    "expiresAt": "2026-07-28T09:30:00Z",
    "anchor": {
      "radiusMeters": 150,
      "isReused": true,
      "recalculationPending": false
    },
    "plazas": [
      {
        "plazaId": "019c...",
        "conversationId": "019c...",
        "name": "文化公园广场",
        "relation": "main",
        "canSpeak": true,
        "unread": {"count": 3, "appearance": "red"}
      }
    ]
  }
}
```

四个广场固定返回 1 个 `main` 和 3 个 `adjacent`。客户端不得自行根据经纬度替换服务端结果。

### 5.3 过期与异常

| 错误码 | 客户端行为 |
|---|---|
| `LOCATION_PERMISSION_REQUIRED` | 展示定位授权引导 |
| `LOCATION_CONTEXT_EXPIRED` | 静默尝试获取新定位并刷新上下文 |
| `LOCATION_ACCURACY_TOO_LOW` | 显示“定位精度不足”，保留可安全使用的旧锚点 |
| `LOCATION_COORDINATE_SYSTEM_INVALID` | 上报客户端错误，不自行转换 |
| `LOCATION_MOVEMENT_SUSPICIOUS` | 限制地理发言并提示重新定位 |
| `LOCATION_OUT_OF_ELIGIBLE_RANGE` | 允许查看历史，但阻止需要当前范围的发言 |

---

## 6. 账号与资料

### 6.1 主要接口

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/auth/sms/send` | 请求短信验证码 |
| POST | `/auth/sms/verify` | 验证并登录/注册 |
| POST | `/auth/refresh` | 刷新登录 |
| POST | `/auth/logout` | 退出当前设备 |
| GET | `/me` | 我的完整资料 |
| PATCH | `/me` | 修改头像、昵称、签名、背景、性别 |
| GET | `/me/privacy` | 我的隐私设置 |
| PATCH | `/me/privacy` | 修改陌生人资料、方圆号搜索等 |
| GET | `/users/{userId}` | 按权限查看他人资料 |
| GET | `/users/{userId}/posts` | 该用户可被当前账号查看的动态 |

### 6.2 他人资料视图

`GET /users/{userId}` 返回当前查看者视角：

```json
{
  "data": {
    "userId": "019c...",
    "fangyuanNumber": "FY123456",
    "nickname": "小桃子",
    "displayName": "桃子",
    "avatar": {},
    "background": {},
    "signature": "周末去打羽毛球",
    "profileVisibility": "full",
    "relationship": {
      "state": "friend",
      "canStartDirectChat": true,
      "isBlockedByMe": false,
      "hasBlockedMe": false,
      "canViewMyPosts": true
    },
    "allowedActions": [
      "openDirectConversation",
      "editRemark",
      "setPostPermission",
      "deleteFriend",
      "block",
      "report"
    ]
  }
}
```

`displayName` 优先使用当前用户设置的备注，否则为对方昵称。未获完整资料权限时，只返回头像、可显示名称和签名，并缩小 `allowedActions`。

所有头像入口只传 `userId`，不得在各页面自行拼接一份“临时个人资料”。

### 6.3 修改资料

```http
PATCH /me
X-Idempotency-Key: ...
```

```json
{
  "expectedVersion": 4,
  "nickname": "小红",
  "gender": "female",
  "signature": "今天也要出去走走",
  "avatarMediaId": "019c...",
  "backgroundMediaId": "019c..."
}
```

若版本已经变化，返回 `409 RESOURCE_VERSION_CONFLICT` 和最新版本摘要，防止两台设备互相覆盖。

---

## 7. 好友、备注与黑名单

### 7.1 好友申请

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/friend-requests` | 发送带说明的申请 |
| GET | `/friend-requests` | 申请列表；待处理优先 |
| POST | `/friend-requests/{requestId}/decision` | 同意或拒绝 |

发送：

```json
{
  "targetUserId": "019c...",
  "applicationNote": "刚才在羽毛球活动里见过"
}
```

决定：

```json
{
  "decision": "accept"
}
```

同意响应必须包含：

```json
{
  "data": {
    "request": {
      "requestId": "019c...",
      "status": "accepted",
      "decidedAt": "2026-07-28T09:40:00Z"
    },
    "friendship": {
      "friendshipId": "019c...",
      "friendUserId": "019c...",
      "state": "active"
    },
    "directConversation": {
      "conversationId": "019c..."
    }
  }
}
```

服务端在一个可靠业务操作中：

1. 把申请改为已同意；
2. 创建唯一好友关系；
3. 创建或恢复唯一私聊会话；
4. 更新双方联系人和消息列表；
5. 通过实时事件通知双方；
6. 不自动发送问候消息。

申请记录不会立刻消失；列表排序把 `pending` 放在最前。

### 7.2 联系人和设置

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/friends` | 联系人列表 |
| PATCH | `/friends/{friendUserId}/settings` | 备注、动态权限、会话置顶 |
| DELETE | `/friends/{friendUserId}` | 删除好友 |

设置：

```json
{
  "remarkName": "阿禾同学",
  "canViewMyPosts": false,
  "pinned": true
}
```

返回最终生效值。备注只影响当前账号的 `displayName`，不得修改对方昵称。

### 7.3 黑名单

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/blocks` | 黑名单 |
| PUT | `/blocks/{targetUserId}` | 拉黑好友或陌生人 |
| DELETE | `/blocks/{targetUserId}` | 解除拉黑 |

拉黑成功响应包括：

```json
{
  "data": {
    "targetUserId": "019c...",
    "state": "blocked",
    "priorRelation": "friend",
    "directMessagingAllowed": false
  }
}
```

规则：

- 有效拉黑存在时，双方私聊都不可发送；
- 发送端收到 `MESSAGE_BLOCKED_RELATION`，气泡显示发送失败；
- 拉黑对象立即进入当前用户黑名单；
- 被拉黑方收到关系/会话能力更新，但不必收到“你被拉黑”的直白推送；
- 解除后，原好友恢复为好友，原陌生人恢复为陌生人；
- 所有变更写审计日志。

---

## 8. 会话与统一聊天

### 8.1 会话摘要

```json
{
  "conversationId": "019c...",
  "type": "place",
  "title": "隆江猪脚饭",
  "avatar": {},
  "lastMessage": {
    "messageId": "019c...",
    "sequence": 980,
    "preview": "今天还有汤吗",
    "createdAt": "2026-07-28T09:45:00Z"
  },
  "unread": {
    "count": 3,
    "appearance": "red",
    "firstUnreadSequence": 978
  },
  "notificationMode": "normal",
  "pinned": false,
  "allowedActions": ["open", "send", "mute", "search"]
}
```

### 8.2 主要接口

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/conversations` | 当前账号的私聊和系统会话 |
| GET | `/conversations/{conversationId}` | 会话详情、身份和规则 |
| GET | `/conversations/{conversationId}/messages` | 历史、补拉或锚点上下文 |
| POST | `/conversations/{conversationId}/messages` | HTTP 发送兜底 |
| PUT | `/conversations/{conversationId}/read-cursor` | 更新已读 |
| PATCH | `/conversations/{conversationId}/settings` | 通知、置顶、公告关闭 |
| GET | `/conversations/{conversationId}/search` | 查找聊天记录 |

广场和附近地点/活动可以不出现在普通“好友消息”会话列表中，但仍使用相同会话详情和消息接口。

### 8.3 消息对象

```json
{
  "messageId": "019c...",
  "clientMessageId": "019c...",
  "conversationId": "019c...",
  "sequence": 981,
  "sender": {
    "userId": "019c...",
    "displayName": "邻里小陈",
    "avatar": {}
  },
  "type": "text",
  "text": "晚上好",
  "payload": null,
  "media": [],
  "replyTo": null,
  "mentions": [],
  "deliveryState": "sent",
  "createdAt": "2026-07-28T09:46:00Z",
  "expiresAt": "2027-07-28T09:46:00Z"
}
```

结构化消息使用 `payload`：

- 位置：地点名、坐标展示权限、地图跳转数据；
- 活动卡片：`activityId` 和卡片快照；
- 系统事件：目标 ID、行为和状态；
- 实时位置：独立会话会话或短期共享会话 ID，不把持续轨迹塞进普通消息。

### 8.4 发送

WebSocket 为主，HTTP 为弱网兜底。两种入口调用同一消息服务。

```json
{
  "clientMessageId": "019c...",
  "type": "text",
  "text": "晚上好",
  "replyToMessageId": null,
  "mentionedUserIds": []
}
```

地理群发言携带 `X-Location-Context`。服务端再次判断：

- 广场是否属于当前四广场；
- 地点/活动是否在有效发现范围，或当前用户是否有不受范围限制的管理/成员资格；
- 群可见和发言规则；
- 禁言和平台限制；
- 媒体是否处理完成；
- 对私聊检查好友和拉黑关系。

### 8.5 已读与“N 条新消息”

```http
PUT /conversations/{conversationId}/read-cursor
```

```json
{
  "lastReadSequence": 981
}
```

服务端只允许游标向前，不允许旧设备把已读回退。返回：

```json
{
  "data": {
    "conversationId": "019c...",
    "lastReadSequence": 981,
    "unread": {
      "count": 0,
      "appearance": "none",
      "firstUnreadSequence": null
    },
    "navigationUnreadDelta": -3
  }
}
```

客户端规则：

- 打开会话先展示底部最新消息；
- 如果 `firstUnreadSequence` 存在，在屏幕中显示“N 条新消息”；
- 点击后用 `anchorSequence` 获取和定位上下文；
- 真正完成阅读后再推进已读游标；
- 游标更新成功后，聊天入口、会话列表和底部导航共同更新；
- 双击底部红点只定位下一个红色未读来源，不显示额外红框或“已定位”提示。

### 8.6 会话通知

```json
{
  "notificationOverride": "muted",
  "pinned": false,
  "announcementDismissedVersion": 3
}
```

`notificationOverride`：

- `inherit`：群类会话继承全局群免打扰；
- `normal`：该会话单独恢复通知；
- `muted`：该会话免打扰。

好友私聊和好友页系统会话不受“全局群免打扰”控制。

---

## 9. 媒体上传

### 9.1 流程

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/media/uploads` | 申请上传 |
| POST | `/media/uploads/{uploadId}/complete` | 确认文件上传完成 |
| GET | `/media/{mediaId}` | 查询处理状态 |

申请：

```json
{
  "purpose": "chat",
  "mediaType": "video",
  "fileName": "clip.mov",
  "contentType": "video/quicktime",
  "bytes": 7340032,
  "durationMs": 18500,
  "width": 1080,
  "height": 1920,
  "sha256": "..."
}
```

响应包含短期上传地址和 `uploadId`。视频超过 20 秒返回 `MEDIA_VIDEO_DURATION_EXCEEDED`，不得等用户上传完才提示。

完成确认后返回 `processing`。只有 `ready` 的媒体才能被动态或消息正式引用。

### 9.2 图片选择

“同一张图片一次发布中只能选择一次”是客户端选择器规则，同时服务端对同一请求中的相同媒体 ID 去重。2–9 张图片的正方形网格属于展示规则，原始媒体尺寸仍保存在媒体对象中。

### 9.3 相机和麦克风

系统相机、相册和麦克风权限由 Flutter 调用操作系统授权：

- 第一次使用时申请；
- 已允许后不重复弹窗；
- 已拒绝时展示前往系统设置的引导；
- 服务端只接收上传结果，不控制系统权限弹窗。

---

## 10. 广场

### 10.1 获取四广场

四广场由 `/geo/context` 返回。广场对象：

```json
{
  "plazaId": "019c...",
  "conversationId": "019c...",
  "name": "文化公园广场",
  "relation": "main",
  "canView": true,
  "canSpeak": true,
  "unread": {
    "count": 3,
    "appearance": "red"
  }
}
```

### 10.2 发言

向广场对应的 `conversationId` 使用统一消息发送。必须携带当前有效位置上下文。

### 10.3 命名

客户端只展示服务端返回的当前名称。名称纠错不会改变 `plazaId` 或 `conversationId`，历史记录不会失联。

---

## 11. 地点

### 11.1 发现

```http
POST /places/discover
X-Location-Context: locctx_opaque
```

```json
{
  "filters": {
    "categoryKeys": [],
    "distanceMeters": 5000,
    "heatLevels": [],
    "historyOnly": false,
    "keyword": null
  },
  "sort": "recommended",
  "cursor": null,
  "limit": 20
}
```

地点卡片返回：

```json
{
  "placeGroupId": "019c...",
  "conversationId": "019c...",
  "name": "隆江猪脚饭",
  "category": {"key": "food", "name": "餐饮"},
  "distance": {"meters": 320, "display": "约320米"},
  "certificationStatus": "verified",
  "heat": {"level": "active", "display": "活跃"},
  "unread": {"count": 3, "appearance": "red"},
  "allowedActions": ["openChat", "viewDetail", "report"]
}
```

热度直接使用五级文字，不使用含义不清的绿点或灰点。

### 11.2 主要接口

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/places/discover` | 附近地点和关键词搜索 |
| GET | `/places/{placeGroupId}` | 地点详情 |
| POST | `/places/{placeGroupId}/claims` | 商家认领 |
| GET | `/me/managed-places` | 我管理的地点，不受当前距离限制 |
| PATCH | `/places/{placeGroupId}/settings` | 群主/管理员修改可见和发言规则 |
| POST | `/places/{placeGroupId}/admins` | 群主任命管理员 |
| DELETE | `/places/{placeGroupId}/admins/{adminUserId}` | 群主移除管理员 |
| PUT | `/places/{placeGroupId}/mutes/{mutedUserId}` | 禁言 |
| DELETE | `/places/{placeGroupId}/mutes/{mutedUserId}` | 解除禁言 |
| POST | `/places/{placeGroupId}/feedback` | 地点信息反馈 |

所有管理响应返回最终生效设置、操作者和更新时间，不允许“按钮点了但没有反馈”。

### 11.3 任命管理员

候选人来源可以是好友搜索或附近用户，但服务端不要求候选人必须是好友：

```json
{
  "candidateUserId": "019c...",
  "expectedPlaceVersion": 7
}
```

只有群主可操作。成功后返回更新后的管理员摘要，并向相关账号推送权限变化事件。

---

## 12. 活动

### 12.1 创建和管理使用同一模型

```json
{
  "name": "周六羽毛球",
  "description": "新手也可以参加",
  "activityType": "badminton",
  "customTypeName": null,
  "location": {
    "coordinateSystem": "gcj02",
    "longitude": 113.264385,
    "latitude": 23.129112,
    "placeName": "滨江体育馆"
  },
  "startsAt": "2026-08-01T10:00:00Z",
  "endsAt": "2026-08-01T12:00:00Z",
  "noFixedEnd": false,
  "visibilityRadiusMeters": 5000,
  "capacity": 20,
  "joinPolicy": "approvalRequired",
  "speakPolicy": "membersOnly",
  "nearbyAfterStartPolicy": "hidden"
}
```

长期活动：

```json
{
  "endsAt": null,
  "noFixedEnd": true
}
```

### 12.2 条件校验

- `activityType=other` 时 `customTypeName` 必填；
- `noFixedEnd=true` 时 `endsAt` 必须为空；
- `noFixedEnd=false` 时结束时间必须晚于开始时间；
- `capacity=null` 表示不限人数；
- 有人数限制时必须为正整数；
- 修改人数不得低于当前有效成员数；
- `joinPolicy=approvalRequired` 时不允许与规则矛盾的附近任意发言组合；
- 修改使用 `expectedVersion` 防止并发覆盖。

### 12.3 主要接口

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/activities` | 创建活动 |
| POST | `/activities/discover` | 附近、爱好、已参加和已结束 |
| GET | `/activities/{activityId}` | 活动详情和当前用户能力 |
| PATCH | `/activities/{activityId}` | 群主/管理员按权限修改 |
| POST | `/activities/{activityId}/join-requests` | 申请或直接加入 |
| GET | `/activities/{activityId}/join-requests` | 管理员查看申请 |
| POST | `/activities/{activityId}/join-requests/{joinRequestId}/decision` | 同意或拒绝 |
| GET | `/activities/{activityId}/members` | 全部成员 |
| PATCH | `/activities/{activityId}/members/{memberUserId}` | 角色、禁言或移除命令 |
| PUT | `/activities/{activityId}/announcement` | 发布/编辑置顶公告 |
| DELETE | `/activities/{activityId}/announcement` | 关闭当前公告 |
| GET/PUT | `/me/activity-expectations` | 活动期待关键词 |

### 12.4 报名审批

审批请求：

```json
{
  "decision": "accept",
  "expectedActivityVersion": 12
}
```

服务端在事务中锁定活动并重新检查容量。若两位管理员同时同意最后一个名额，只能一位成功，另一位返回 `ACTIVITY_FULL`。

审批完成后申请仍保留并显示 `accepted` 或 `rejected`。活动通知中的申请人头像携带 `userId`，点击打开统一资料。

### 12.5 公告

公告有递增 `version`。成员关闭公告时，只更新自己的 `announcementDismissedVersion`，不会删除其他人的公告。

---

## 13. 动态

### 13.1 发布

```http
POST /posts
X-Idempotency-Key: ...
X-Location-Context: locctx_opaque
```

```json
{
  "body": "今天的天气不错",
  "mediaIds": ["019c..."],
  "radiusMeters": 1000,
  "showPlaceName": true,
  "placeName": "文化公园",
  "visibleUntil": null
}
```

服务端返回 `editableUntil`。媒体必须全部为当前用户拥有且状态为 `ready`。

### 13.2 主要接口

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/posts/discover` | 附近最新、热门、距离和日期筛选 |
| GET | `/feeds/friends` | 好友动态，新到旧 |
| POST | `/posts` | 发布 |
| GET | `/posts/{postId}` | 统一动态详情 |
| PATCH | `/posts/{postId}` | 1 分钟内编辑 |
| DELETE | `/posts/{postId}` | 二次确认后删除 |
| PUT/DELETE | `/posts/{postId}/like` | 点赞/取消 |
| POST | `/posts/{postId}/comments` | 评论主动态或回复评论 |
| PUT/DELETE | `/comments/{commentId}/like` | 评论点赞/取消 |
| POST | `/posts/{postId}/report` | 举报动态 |

### 13.3 详情复用

任何入口打开动态只使用：

```text
GET /posts/{postId}
```

返回同一条正文、媒体、点赞、评论和当前用户互动状态。列表卡片可以使用相同 `Post` 模型的简化字段，但不得复制成独立数据。

### 13.4 评论

评论主动态：

```json
{
  "body": "拍得不错",
  "parentCommentId": null,
  "replyToUserId": null
}
```

回复评论：

```json
{
  "body": "哈哈哈",
  "parentCommentId": "019c_comment",
  "replyToUserId": "019c_user"
}
```

Flutter 点击评论者头像或 @用户名时使用 `replyToUserId` / `author.userId` 打开统一资料。点击评论区只弹出当前动态详情页上的输入框，不切回广场动态列表。

### 13.5 通知定位

动态通知结构化消息至少包含：

```json
{
  "eventType": "post.comment.created",
  "actorUserId": "019c...",
  "postId": "019c...",
  "commentId": "019c...",
  "preview": "拍得不错"
}
```

点击后直接打开 `postId` 对应动态详情，可按需要定位 `commentId`。

---

## 14. 系统会话、通知和全局同步

### 14.1 系统会话

每个账号固定拥有：

- 好友申请；
- 活动通知；
- 动态通知；
- 发现期待活动。

它们属于 `system` 会话，和普通消息共同使用会话摘要、未读和已读接口。结构化卡片放在消息 `payload`。

### 14.2 全局群免打扰

```http
PATCH /me/notification-settings
```

```json
{
  "globalGroupMuted": true
}
```

只影响广场、地点和活动的默认通知模式，不影响好友私聊和好友页系统会话。

### 14.3 增量同步

```http
GET /sync/events?afterCursor=<opaque>&limit=100
```

返回当前账号跨设备的重要变化：

- 好友关系；
- 黑名单；
- 会话摘要和未读；
- 资料和隐私；
- 活动报名；
- 管理权限；
- 内容被删除或处置。

WebSocket 断线重连后先尝试 `resumeCursor`；无法恢复时使用 REST 增量同步，不要求全量刷新所有页面。

---

## 15. 全局搜索

```http
POST /search
```

```json
{
  "query": "羽毛球",
  "locationContextToken": "locctx_opaque",
  "categories": [
    "friends",
    "plazaMessages",
    "directMessages",
    "places",
    "activities",
    "systemConversations"
  ],
  "perCategoryLimit": 3
}
```

响应按类别分组：

```json
{
  "data": {
    "groups": [
      {
        "category": "activities",
        "items": [],
        "hasMore": true,
        "moreCursor": "opaque"
      }
    ]
  }
}
```

规则：

- 不同类别独立匹配和评分；
- 没有关联的好友不得因模糊算法误出现；
- 地点和活动直接返回可复用卡片；
- 聊天记录结果带 `conversationId` 和 `messageSequence`；
- 系统会话可匹配“好友申请”“动态通知”等名称；
- 单类默认最多 3 条，更多内容用该类游标查看。

---

## 16. 举报、反馈和审计

统一举报请求：

```json
{
  "targetType": "post",
  "targetId": "019c...",
  "reasonCode": "other",
  "description": "具体说明",
  "evidenceMediaIds": ["019c..."]
}
```

- `reasonCode=other` 时说明必填；
- 图片和视频必须先通过媒体上传接口；
- 返回举报单 ID 和处理状态；
- 普通用户不能读取他人举报；
- 审核操作记录审计；
- 被举报内容的普通保存期到期时，如处于合规冻结则暂不物理删除。

---

## 17. WebSocket 契约

完整事件定义见 `api/asyncapi-v1.yaml`。

### 17.1 连接

```text
wss://realtime.fangyuanli.example/ws/v1
Authorization: Bearer <accessToken>
X-Device-Id: <deviceId>
```

建立后客户端发送：

```json
{
  "event": "session.resume",
  "requestId": "019c...",
  "payload": {
    "resumeCursor": "opaque-or-null"
  }
}
```

服务端返回：

```json
{
  "event": "session.ready",
  "eventId": "019c...",
  "eventCursor": "opaque",
  "serverTime": "2026-07-28T09:50:00Z",
  "payload": {
    "resumed": true,
    "heartbeatIntervalSeconds": 25
  }
}
```

### 17.2 发送确认

客户端：

```json
{
  "event": "message.send",
  "requestId": "019c_request",
  "payload": {
    "conversationId": "019c_conversation",
    "clientMessageId": "019c_client_message",
    "type": "text",
    "text": "晚上好"
  }
}
```

服务端先向发送设备确认：

```json
{
  "event": "message.accepted",
  "requestId": "019c_request",
  "eventId": "019c_event",
  "eventCursor": "opaque",
  "payload": {
    "clientMessageId": "019c_client_message",
    "messageId": "019c_message",
    "conversationId": "019c_conversation",
    "sequence": 981,
    "createdAt": "2026-07-28T09:50:02Z"
  }
}
```

再向有资格的相关设备推送 `message.created`。客户端按 `messageId` / `clientMessageId` 合并，不能显示两次。

失败：

```json
{
  "event": "message.rejected",
  "requestId": "019c_request",
  "payload": {
    "clientMessageId": "019c_client_message",
    "error": {
      "code": "MESSAGE_BLOCKED_RELATION",
      "message": "消息发送失败"
    }
  }
}
```

### 17.3 心跳与重连

- 服务端下发心跳间隔；
- 客户端进入后台时遵守系统限制，不维持高频无意义心跳；
- 重连使用指数退避和随机抖动；
- 前台恢复优先重连并携带 `resumeCursor`；
- 缺失事件通过 `/sync/events` 补齐；
- 不能把“WebSocket 已连接”当作消息已经保存，必须等待 `message.accepted`。

---

## 18. 核心错误码

### 18.1 通用

| 错误码 | HTTP | 含义 |
|---|---:|---|
| `INVALID_ARGUMENT` | 400 | 字段不合法 |
| `AUTH_REQUIRED` | 401 | 需要登录 |
| `AUTH_TOKEN_EXPIRED` | 401 | Access Token 过期 |
| `ACCOUNT_DISABLED` | 403 | 账号受限 |
| `RESOURCE_NOT_FOUND` | 404 | 不存在或不可见 |
| `RESOURCE_VERSION_CONFLICT` | 409 | 并发版本冲突 |
| `IDEMPOTENCY_CONFLICT` | 409 | 同一幂等键请求内容不同 |
| `RATE_LIMITED` | 429 | 操作过于频繁 |

### 18.2 好友和消息

| 错误码 | HTTP | 含义 |
|---|---:|---|
| `FRIEND_REQUEST_NOTE_REQUIRED` | 422 | 申请说明必填 |
| `FRIEND_REQUEST_ALREADY_PENDING` | 409 | 已有待处理申请 |
| `FRIENDSHIP_ALREADY_EXISTS` | 409 | 已是好友 |
| `FRIENDSHIP_REQUIRED` | 403 | 必须先成为好友 |
| `BLOCK_RELATION_ACTIVE` | 403 | 当前关系被拉黑限制 |
| `MESSAGE_BLOCKED_RELATION` | 403 | 因拉黑无法发送 |
| `MESSAGE_MEDIA_NOT_READY` | 422 | 媒体未处理完成 |
| `MESSAGE_FORBIDDEN` | 403 | 无当前会话发言资格 |
| `MESSAGE_EXPIRED` | 410 | 目标内容已过期 |

### 18.3 地理、地点和活动

| 错误码 | HTTP | 含义 |
|---|---:|---|
| `LOCATION_CONTEXT_REQUIRED` | 403 | 缺少位置上下文 |
| `LOCATION_CONTEXT_EXPIRED` | 401 | 位置上下文已过期 |
| `LOCATION_ACCURACY_TOO_LOW` | 422 | 精度不足 |
| `LOCATION_OUT_OF_ELIGIBLE_RANGE` | 403 | 不满足当前地理资格 |
| `PLACE_MANAGE_FORBIDDEN` | 403 | 无地点管理权限 |
| `ACTIVITY_FULL` | 409 | 活动人数已满 |
| `ACTIVITY_JOIN_ALREADY_PENDING` | 409 | 已提交申请 |
| `ACTIVITY_CAPACITY_BELOW_MEMBER_COUNT` | 422 | 新上限低于当前人数 |
| `ACTIVITY_RULE_CONFLICT` | 422 | 加入和发言规则矛盾 |
| `ACTIVITY_ENDED` | 410 | 活动已结束且当前操作不可用 |

### 18.4 动态和媒体

| 错误码 | HTTP | 含义 |
|---|---:|---|
| `POST_EDIT_WINDOW_EXPIRED` | 403 | 已超过 1 分钟编辑期 |
| `POST_VISIBILITY_DENIED` | 404 | 当前无权查看 |
| `POST_MEDIA_DUPLICATED` | 422 | 同一媒体重复添加 |
| `MEDIA_VIDEO_DURATION_EXCEEDED` | 413 | 视频超过 20 秒 |
| `MEDIA_RESOLUTION_EXCEEDED` | 422 | 视频超过允许分辨率 |
| `MEDIA_TYPE_UNSUPPORTED` | 415 | 不支持的格式 |
| `MEDIA_UPLOAD_INCOMPLETE` | 422 | 文件未完成上传 |

---

## 19. 契约测试清单

### 19.1 双账号好友测试

1. A 申请 B，B 的好友申请系统会话出现红色未读。
2. B 同意后申请显示“已同意”，不立即消失。
3. A、B 联系人同时出现对方。
4. 双方获得同一个私聊关系，不自动出现问候语。
5. A 给 B 设置备注，不改变 B 的昵称和 B 看到的名称。
6. A 拉黑 B 后，双方发消息均失败且 A 黑名单出现 B。
7. A 解除后恢复原好友；若拉黑前是陌生人则恢复陌生人。

### 19.2 动态复用测试

1. A 发布文字 + 图片动态。
2. 广场动态、A 的个人资料显示同一文字和图片。
3. 好友 B 的好友动态显示同一内容但不显示距离和“好友可见”。
4. 点赞评论数在所有入口一致。
5. 动态通知点击进入同一详情并能定位评论。
6. 评论头像、@用户名均进入正确个人资料。

### 19.3 未读测试

1. 为一个会话准备足够长的历史和 5 条未读。
2. 打开默认在底部，同时显示“5 条新消息”。
3. 点击定位第一条未读。
4. 完成阅读后会话红点、底部导航计数和入口共同消失。
5. 免打扰会话显示灰点，不计入底部导航且不推送。
6. 第二台设备读取后，第一台通过实时事件或增量同步清零。

### 19.4 活动并发测试

1. 活动已有 8 人，设置上限 7 返回明确错误。
2. 最后一个名额被两名管理员同时审批，只允许一人成功。
3. 创建和管理页面写入同一套加入、发言和附近规则。
4. 活动公告关闭只影响当前成员设备。
5. 长期活动可由群主设置结束时间，管理员不能越权。

### 19.5 地理测试

1. 锚点 150 米内 GPS 漂移不切换四广场。
2. 超过锚点但定位精度差时不立即切换。
3. 连续定位和停留满足条件后稳定切换。
4. 四广场都可发言，等距相邻广场顺序稳定。
5. API 不向其他用户返回当前账号精准坐标。

---

## 20. 本版本边界与下一步

本契约 v0.1 已固定：

- 通用 REST 规范；
- 位置上下文；
- 账号资料；
- 好友、黑名单和私聊；
- 统一会话、消息、已读、免打扰；
- 媒体上传；
- 广场、地点、活动、动态；
- 系统通知、搜索、举报；
- WebSocket 确认、重连和同步；
- 第一批稳定错误码和测试链路。

尚未锁死：

- 短信供应商和实名策略；
- Token 具体有效期；
- 高德坐标与 PostGIS 的最终存储实现；
- 推送合并频率；
- 热度公式阈值；
- 运营后台的完整内部 API；
- 支付、商业化、推荐算法和复杂 AI 审核。

技术选型已经确定为 Flutter、Node.js 24 LTS、TypeScript、NestJS 11 + Fastify、PostgreSQL 18 + PostGIS、Kysely 和 Redis。下一步是准备腾讯云 staging 环境，随后在服务器建立正式仓库和第一条双账号好友/私聊端到端链路。
