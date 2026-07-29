export type Gender = "unspecified" | "male" | "female" | "custom";

export type RelationshipState =
  | "self"
  | "stranger"
  | "requestPending"
  | "friend"
  | "blocked";

export type RelationshipView = {
  state: RelationshipState;
  canStartDirectChat: boolean;
  isBlockedByMe: boolean;
  hasBlockedMe: boolean;
  canViewMyPosts: boolean;
};

export type ProfileView = {
  userId: string;
  displayName: string;
  avatar: null;
  fangyuanNumber: string | null;
  nickname: string | null;
  gender: Gender | "hidden";
  signature: string;
  background: null;
  profileVisibility: "full" | "limited";
  profileVersion: number;
  relationship: RelationshipView;
  allowedActions: string[];
};

export type PrivacySettingsView = {
  strangersCanViewProfile: boolean;
  searchableByFangyuanNumber: boolean;
  globalGroupMuted: boolean;
  updatedAt: string;
};

export type ProfilePatch = {
  expectedVersion: number;
  nickname?: string;
  gender?: Gender;
  customGender?: string | null;
  signature?: string;
};

export type PrivacyPatch = {
  strangersCanViewProfile?: boolean;
  searchableByFangyuanNumber?: boolean;
  globalGroupMuted?: boolean;
};

export class ProfileDomainError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly status: number
  ) {
    super(message);
  }
}
