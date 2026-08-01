import { Global, Module } from "@nestjs/common";
import { Pool } from "pg";
import {
  requireDatabaseUrl,
  resolveDatabasePoolMax
} from "./environment.js";
import { DATABASE_POOL, DatabaseService } from "./database.service.js";

@Global()
@Module({
  providers: [
    {
      provide: DATABASE_POOL,
      useFactory: () =>
        new Pool({
          application_name:
            process.env.FANGYUANLI_PROCESS_ROLE?.trim() || "fangyuanli-api",
          connectionString: requireDatabaseUrl(process.env),
          max: resolveDatabasePoolMax(process.env)
        })
    },
    DatabaseService
  ],
  exports: [DatabaseService]
})
export class DatabaseModule {}
