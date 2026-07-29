import { Global, Module } from "@nestjs/common";
import { RealtimeConnectionRegistry } from "./realtime-connection-registry.js";
import { RealtimeEventStore } from "./realtime-event-store.js";
import { RealtimeTransport } from "./realtime-transport.js";

@Global()
@Module({
  providers: [
    RealtimeConnectionRegistry,
    RealtimeEventStore,
    RealtimeTransport
  ],
  exports: [RealtimeConnectionRegistry, RealtimeTransport]
})
export class RealtimeInfrastructureModule {}
