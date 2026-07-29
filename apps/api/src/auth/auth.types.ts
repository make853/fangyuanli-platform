export type DeviceInput = {
  deviceId: string;
  platform: "ios" | "android";
  deviceName?: string;
};

export type AuthTokens = {
  accessToken: string;
  accessTokenExpiresAt: string;
  refreshToken: string;
  refreshTokenExpiresAt: string;
};

export type AuthResponse = AuthTokens & {
  deviceId: string;
  userId: string;
  isNewUser: boolean;
};

export type SmsSendResponse = {
  verificationId: string;
  expiresAt: string;
  resendAfterSeconds: number;
};

export class AuthDomainError extends Error {
  constructor(
    public readonly code: string,
    message: string,
    public readonly status: number
  ) {
    super(message);
  }
}
