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
import { PlaceService } from "./place.service.js";
import { PlaceDomainError } from "./place.types.js";

@Controller("places")
@UseGuards(AccessTokenGuard)
export class PlaceController {
  constructor(private readonly places: PlaceService) {}

  @Post("discover")
  discover(
    @CurrentUserId() userId: string,
    @Headers("x-location-context") locationContextToken: string | undefined,
    @Body() body: Record<string, unknown>,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () => this.places.discover({ userId, locationContextToken, body }),
      requestId
    );
  }

  private async respond<T>(
    action: () => Promise<T>,
    requestId?: string
  ): Promise<{ data: T; meta: { requestId: string; serverTime: string } }> {
    const resolvedRequestId = requestId?.trim() || randomUUID();
    try {
      return {
        data: await action(),
        meta: { requestId: resolvedRequestId, serverTime: new Date().toISOString() }
      };
    } catch (error) {
      if (error instanceof PlaceDomainError) {
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
