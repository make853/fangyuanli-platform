import {
  Body,
  Controller,
  Headers,
  HttpException,
  Post,
  UseGuards
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { AccessTokenGuard } from "../auth/access-token.guard.js";
import { CurrentUserId } from "../auth/current-user.decorator.js";
import { GeoContextService } from "./geo-context.service.js";
import { GeoDomainError } from "./plaza-context.types.js";

@Controller("geo")
@UseGuards(AccessTokenGuard)
export class GeoController {
  constructor(private readonly geoContexts: GeoContextService) {}

  @Post("context")
  async createContext(
    @CurrentUserId() userId: string,
    @Body() body: Record<string, unknown>,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    const resolvedRequestId = requestId?.trim() || randomUUID();
    try {
      return {
        data: await this.geoContexts.create({ userId, body }),
        meta: {
          requestId: resolvedRequestId,
          serverTime: new Date().toISOString()
        }
      };
    } catch (error) {
      if (error instanceof GeoDomainError) {
        throw new HttpException(
          {
            error: {
              code: error.code,
              message: error.message,
              requestId: resolvedRequestId
            }
          },
          error.status
        );
      }
      throw error;
    }
  }
}
