import { Injectable } from "@nestjs/common";
import { createHmac } from "node:crypto";

@Injectable()
export class RequestHasher {
  hash(value: string): string {
    const secret = process.env.REQUEST_HASH_KEY?.trim();
    if (!secret || secret.length < 32) {
      throw new Error("REQUEST_HASH_KEY must contain at least 32 characters");
    }
    return createHmac("sha256", secret).update(value).digest("hex");
  }
}
