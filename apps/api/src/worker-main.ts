import "reflect-metadata";
import { NestFactory } from "@nestjs/core";
import { randomUUID } from "node:crypto";
import { hostname } from "node:os";
import { MediaProcessingWorker } from "./media/media-processing.worker.js";
import { WorkerModule } from "./worker.module.js";

const app = await NestFactory.createApplicationContext(WorkerModule, {
  logger: false
});

const abortController = new AbortController();
const stop = () => abortController.abort();
process.once("SIGINT", stop);
process.once("SIGTERM", stop);

const workerId = `${hostname()}:${process.pid}:${randomUUID()}`;
try {
  await app.get(MediaProcessingWorker).run(workerId, abortController.signal);
} finally {
  process.removeListener("SIGINT", stop);
  process.removeListener("SIGTERM", stop);
  await app.close();
}
