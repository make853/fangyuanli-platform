import { createParamDecorator, type ExecutionContext } from "@nestjs/common";
import type { AuthenticatedRequest } from "./access-token.guard.js";

export const CurrentUserId = createParamDecorator(
  (_data: unknown, context: ExecutionContext): string => {
    return context.switchToHttp().getRequest<AuthenticatedRequest>().auth.userId;
  }
);
