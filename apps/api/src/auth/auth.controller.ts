import {
  Body,
  Controller,
  Headers,
  HttpCode,
  HttpException,
  Post
} from "@nestjs/common";
import { randomUUID } from "node:crypto";
import { AuthService } from "./auth.service.js";
import { AuthDomainError } from "./auth.types.js";

@Controller("auth")
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post("sms/send")
  @HttpCode(200)
  async sendSms(
    @Body() body: Record<string, unknown>,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () => this.auth.sendSms(body),
      requestId
    );
  }

  @Post("sms/verify")
  @HttpCode(200)
  async verifySms(
    @Body() body: Record<string, unknown>,
    @Headers("idempotency-key") idempotencyKey?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () => this.auth.verifySms({ ...body, idempotencyKey }),
      requestId
    );
  }

  @Post("refresh")
  @HttpCode(200)
  async refresh(
    @Body() body: Record<string, unknown>,
    @Headers("x-request-id") requestId?: string
  ): Promise<unknown> {
    return this.respond(
      () => this.auth.refresh(body),
      requestId
    );
  }

  @Post("logout")
  @HttpCode(204)
  async logout(
    @Headers("authorization") authorization?: string,
    @Headers("x-device-id") deviceId?: string,
    @Headers("x-request-id") requestId?: string
  ): Promise<void> {
    try {
      await this.auth.logout({ authorization, deviceId });
    } catch (error) {
      this.throwHttp(error, requestId);
    }
  }

  private async respond<T>(
    action: () => Promise<T>,
    requestId?: string
  ): Promise<{ data: T; meta: { requestId: string; serverTime: string } }> {
    const resolvedRequestId = requestId?.trim() || randomUUID();
    try {
      return {
        data: await action(),
        meta: {
          requestId: resolvedRequestId,
          serverTime: new Date().toISOString()
        }
      };
    } catch (error) {
      this.throwHttp(error, resolvedRequestId);
    }
  }

  private throwHttp(error: unknown, requestId?: string): never {
    if (error instanceof AuthDomainError) {
      throw new HttpException(
        {
          error: {
            code: error.code,
            message: error.message,
            requestId: requestId?.trim() || randomUUID()
          }
        },
        error.status
      );
    }
    throw error;
  }
}
