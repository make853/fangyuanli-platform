import '../../conversations/domain/community_chat_models.dart';
import '../domain/activity_models.dart';

abstract final class ActivityPreviewCatalog {
  static const messages = [
    CommunityMessagePreview(
      id: 'activity-message-1',
      senderName: '林间小路',
      text: '我会提前十分钟到，谁需要我顺便带球？',
    ),
    CommunityMessagePreview(
      id: 'activity-message-2',
      senderName: '董事长',
      text: '我带两筒新球。',
      isMine: true,
    ),
  ];

  static const activities = [
    ActivitySummary(
      id: 'badminton',
      name: '周六羽毛球缺2人',
      statusLabel: '我创建的 · 即将开始',
      timeLabel: '今天 15:00—17:00',
      locationName: '云动体育馆',
      distanceMeters: 1200,
      memberLabel: '8/10人',
      introduction: '适合有基础的球友，现场AA场地费用，请自带球拍和饮用水。',
      joinRule: '需要管理员批准',
      chatRule: '只有已加入成员可以聊天',
      creatorName: '董事长',
      views: {
        ActivityListView.nearby,
        ActivityListView.interests,
        ActivityListView.joined,
      },
      unreadCount: 2,
      announcement: '请提前十分钟到场，临时有事请在群里说明。',
    ),
    ActivitySummary(
      id: 'music',
      name: '城市音乐节现场群',
      statusLabel: '今晚开始',
      timeLabel: '今天 19:30—22:30',
      locationName: '北岸公园',
      distanceMeters: 4800,
      memberLabel: '126人 · 不限人数',
      introduction: '供现场观众交流入场、交通和散场信息，不代表活动主办方。',
      joinRule: '直接加入',
      chatRule: '附近所有人都可以聊天',
      creatorName: '远山',
      views: {ActivityListView.nearby, ActivityListView.joined},
      unreadCount: 12,
    ),
    ActivitySummary(
      id: 'run',
      name: '滨江夜跑 · 轻松5公里',
      statusLabel: '明天',
      timeLabel: '明天 20:00—21:30',
      locationName: '滨江步道入口',
      distanceMeters: 2300,
      memberLabel: '17人 · 不限人数',
      introduction: '轻松配速，适合刚开始规律跑步的朋友。',
      joinRule: '直接加入',
      chatRule: '只有已加入成员可以聊天',
      creatorName: '林间小路',
      views: {ActivityListView.nearby, ActivityListView.interests},
    ),
    ActivitySummary(
      id: 'swim',
      name: '上周游泳交流',
      statusLabel: '已结束 · 群聊开放',
      timeLabel: '7月20日 18:30—20:00',
      locationName: '蓝湾游泳馆',
      distanceMeters: 1800,
      memberLabel: '24位参与者',
      introduction: '活动已结束，参与者仍可查看记录和继续交流。',
      joinRule: '活动已结束',
      chatRule: '已报名成员可以继续聊天',
      creatorName: '阿禾',
      views: {
        ActivityListView.interests,
        ActivityListView.joined,
        ActivityListView.ended,
      },
    ),
  ];
}
