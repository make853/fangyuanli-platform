export class RelationshipDomainError extends Error {
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

export type FriendRequestView = {
  requestId: string;
  sender: UserSummary;
  receiver: UserSummary;
  status: "pending" | "accepted" | "rejected" | "cancelled" | "expired";
  applicationNote: string;
  createdAt: string;
  decidedAt: string | null;
};

export type FriendDecisionView = {
  request: FriendRequestView;
  friendshipId: string | null;
  friendUserId: string | null;
  directConversationId: string | null;
};

export type FriendView = UserSummary & {
  nickname: string;
  remarkName: string | null;
  canViewMyPosts: boolean;
  pinned: boolean;
  directConversationId: string;
  updatedAt: string;
};

export type BlockView = {
  target: UserSummary;
  state: "blocked" | "unblocked";
  priorRelation: "friend" | "stranger";
  restoredRelation: "friend" | "stranger" | null;
  directMessagingAllowed: boolean;
  updatedAt: string;
};
