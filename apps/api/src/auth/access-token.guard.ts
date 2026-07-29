import {
  CanActivate,
  ExecutionContext,
  Injectable,
  UnauthorizedException
} from "@nestjs/common";
import type { FastifyRequest } from "fastify";
import { AuthRepository } from "./auth.repository.js";
import { TokenService, type AccessClaims } from "./token-service.js";

export type AuthenticatedRequest = FastifyRequest & {
  auth: AccessClaims;
};

@Injectable()
export class AccessTokenGuard implements CanActivate {
  constructor(
    private readonly tokens: TokenService,
    private readonly repository: AuthRepository
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const authorization = request.headers.authorization;
    const token = authorization?.match(/^Bearer (.+)$/i)?.[1];
    if (!token) {
      throw new UnauthorizedException({
        error: { code: "AUTH_REQUIRED", message: "请先登录" }
      });
    }

    try {
      const claims = await this.tokens.verifyAccessToken(token);
      if (!(await this.repository.isSessionActive(claims))) {
        throw new Error("Session is inactive");
      }
      request.auth = claims;
      return true;
    } catch {
      throw new UnauthorizedException({
        error: { code: "AUTH_REQUIRED", message: "登录状态已失效" }
      });
    }
  }
}
