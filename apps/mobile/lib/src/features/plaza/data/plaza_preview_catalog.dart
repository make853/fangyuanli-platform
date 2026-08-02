import '../../conversations/domain/community_chat_models.dart';
import '../domain/plaza_models.dart';

abstract final class PlazaPreviewCatalog {
  static const plazas = [
    PlazaSummary(
      id: 'primary',
      name: '方圆广场',
      activePeople: 28,
      isPrimary: true,
    ),
    PlazaSummary(
      id: 'east',
      name: '东街广场',
      activePeople: 41,
      isPrimary: false,
      unreadCount: 12,
    ),
    PlazaSummary(
      id: 'river',
      name: '滨河广场',
      activePeople: 23,
      isPrimary: false,
      unreadCount: 6,
    ),
    PlazaSummary(
      id: 'culture',
      name: '文化路广场',
      activePeople: 17,
      isPrimary: false,
      unreadCount: 3,
    ),
  ];

  static const messages = [
    CommunityMessagePreview(
      id: 'plaza-message-1',
      senderName: '林间小路',
      text: '楼下新开的咖啡店今天试营业，有人去过吗？',
    ),
    CommunityMessagePreview(
      id: 'plaza-message-2',
      senderName: '周末有空',
      text: '刚路过，人还挺多。下午一起去看看 ☕️',
    ),
    CommunityMessagePreview(
      id: 'plaza-message-3',
      senderName: '董事长',
      text: '可以，我四点左右过去。',
      isMine: true,
    ),
  ];
}
