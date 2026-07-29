process.env.DATABASE_URL ??=
  "postgresql://smoke:smoke@127.0.0.1:5432/fangyuanli_smoke";

const { createApp } = await import("../dist/bootstrap.js");
const app = await createApp();

try {
  await app.init();
} finally {
  await app.close();
}
