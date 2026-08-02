import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module.js";
import { GeoModule } from "../geo/geo.module.js";
import { PlaceCandidateProvider } from "./place-candidate.provider.js";
import { PlaceCardPresenter } from "./place-card.presenter.js";
import { PlaceCategoryMapper } from "./place-category.mapper.js";
import { PlaceController } from "./place.controller.js";
import { PlaceDiscoveryInput } from "./place-discovery.input.js";
import { PlaceRepository } from "./place.repository.js";
import { PlaceService } from "./place.service.js";

@Module({
  imports: [AuthModule, GeoModule],
  controllers: [PlaceController],
  providers: [
    PlaceRepository,
    PlaceCandidateProvider,
    PlaceCardPresenter,
    PlaceCategoryMapper,
    PlaceDiscoveryInput,
    PlaceService
  ]
})
export class PlaceModule {}
