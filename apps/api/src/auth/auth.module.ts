import { Module } from "@nestjs/common";
import { AuthController } from "./auth.controller.js";
import { AuthRepository } from "./auth.repository.js";
import { AuthService } from "./auth.service.js";
import { AccessTokenGuard } from "./access-token.guard.js";
import { PhoneIdentityService } from "./phone-identity.js";
import { TokenService } from "./token-service.js";

@Module({
  controllers: [AuthController],
  providers: [
    AccessTokenGuard,
    AuthRepository,
    AuthService,
    {
      provide: PhoneIdentityService,
      useFactory: () => new PhoneIdentityService()
    },
    {
      provide: TokenService,
      useFactory: () => new TokenService()
    }
  ],
  exports: [AccessTokenGuard, AuthRepository, TokenService]
})
export class AuthModule {}
