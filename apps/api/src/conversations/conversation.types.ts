export class ConversationDomainError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly status: number
  ) {
    super(message);
  }
}

export type UserSummary = {
  userId: string;
  displayName: string;
  avatar: null;
};

export type UnreadState = {
  count: number;
  appearance: "none" | "red" | "gray";
  firstUnreadSequence: number | null;
};

export type MessageView = {
  messageId: string;
  clientMessageId: string | null;
  conversationId: string;
  sequence: number;
  sender: UserSummary | null;
  type: "text";
  text: string | null;
  payload: Record<string, unknown> | null;
  media: [];
  replyToMessageId: string | null;
  mentions: [];
  deliveryState: "sent" | "expired" | "deleted" | "failed";
  createdAt: string;
  expiresAt: string | null;
};

export type ConversationSummary = {
  conversationId: string;
  type: "direct";
  title: string;
  avatar: null;
  lastMessage: {
    messageId: string;
    sequence: number;
    preview: string;
    createdAt: string;
  } | null;
  unread: UnreadState;
  notificationMode: "normal" | "muted";
  pinned: boolean;
  allowedActions: string[];
};

export type ConversationDetail = ConversationSummary & {
  latestSequence: number;
  currentRole: "friend" | "formerFriend" | "blocked";
  rules: {
    canViewHistory: true;
    canSendMessage: boolean;
  };
  announcement: null;
};

export type ReadCursorView = {
  conversationId: string;
  lastReadSequence: number;
  unread: UnreadState;
  navigationUnreadDelta: number;
};
