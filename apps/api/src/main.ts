import { createApp } from "./bootstrap.js";
import { resolveListenOptions } from "./runtime-config.js";

const app = await createApp();
await app.listen(resolveListenOptions(process.env));
