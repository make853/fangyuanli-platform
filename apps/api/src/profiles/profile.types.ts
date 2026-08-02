import type {
  MediaDeliveryReference,
  MediaView
} from "../media/media.types.js";

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
  avatar: MediaView | null;
  fangyuanNumber: string | null;
  nickname: string | null;
  gender: Gender | "hidden";
  signature: string;
  background: MediaView | null;
  profileVisibility: "full" | "limited";
  profileVersion: number;
  relationship: RelationshipView;
  allowedActions: string[];
};

export type ProfileProjection = Omit<ProfileView, "avatar" | "background"> & {
  avatarReference: MediaDeliveryReference | null;
  backgroundReference: MediaDeliveryReference | null;
};

export type UserIdentityProjection = {
  userId: string;
  displayName: string;
  profileVersion: number;
  avatarReference: MediaDeliveryReference | null;
};

export type UserIdentityView = {
  userId: string;
  displayName: string;
  profileVersion: number;
  avatar: MediaView | null;
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
  avatarMediaId?: string | null;
  backgroundMediaId?: string | null;
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
