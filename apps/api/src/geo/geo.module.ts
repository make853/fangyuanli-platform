import { Module } from "@nestjs/common";
import { LocationContextReader } from "./location-context.js";

@Module({
  providers: [LocationContextReader],
  exports: [LocationContextReader]
})
export class GeoModule {}
