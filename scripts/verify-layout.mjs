import { access, readFile } from "node:fs/promises";
import path from "node:path";
import process from "node:process";

const root = process.cwd();
const required = [
  "apps/mobile",
  "apps/api",
  "apps/worker",
  "apps/admin-web",
  "packages/contracts/openapi-v1.yaml",
  "packages/contracts/asyncapi-v1.yaml",
  "database/model.dbml",
  "docs/product/PRODUCT_SPEC.md",
  "docs/architecture/TECHNICAL_PLAN.md",
  "compose.yaml",
  ".env.example"
];

for (const relative of required) {
  await access(path.join(root, relative));
}

const ignored = await readFile(path.join(root, ".gitignore"), "utf8");
for (const pattern of [".env", "*.pem", "*.p12", "secrets/"]) {
  if (!ignored.includes(pattern)) {
    throw new Error(`.gitignore 缺少敏感文件规则: ${pattern}`);
  }
}

console.log("Formal repository layout verified.");
