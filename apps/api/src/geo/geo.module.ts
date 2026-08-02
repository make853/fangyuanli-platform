import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { GeoContextInput } from "./geo-context.input.js";
import { GeoContextService } from "./geo-context.service.js";
import { GeoController } from "./geo.controller.js";
import { LocationContextReader } from "./location-context.js";
import { PlazaAnchorPolicy } from "./plaza-anchor-policy.js";
import { AmapPlazaNamingProvider } from "./amap-plaza-naming.provider.js";
import { PlazaContextRepository } from "./plaza-context.repository.js";
import { PlazaGridProjector } from "./plaza-grid-projector.js";
import { PlazaNameSelector } from "./plaza-name-selector.js";
import { PlazaNamingProvider } from "./plaza-naming.provider.js";
import { PlazaNamingService } from "./plaza-naming.service.js";
import { PlazaPolicy } from "./plaza-policy.js";

@Module({
  imports: [AuthModule],
  controllers: [GeoController],
  providers: [
    GeoContextInput,
    GeoContextService,
    LocationContextReader,
    PlazaAnchorPolicy,
    PlazaContextRepository,
    PlazaGridProjector,
    PlazaNameSelector,
    PlazaNamingService,
    {
      provide: PlazaNamingProvider,
      inject: [PlazaNameSelector],
      useFactory: (selector: PlazaNameSelector) =>
        new AmapPlazaNamingProvider(selector)
    },
    {
      provide: PlazaPolicy,
      useFactory: () => new PlazaPolicy()
    }
  ],
  exports: [LocationContextReader]
})
export class GeoModule {}
