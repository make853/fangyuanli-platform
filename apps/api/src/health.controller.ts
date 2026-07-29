import { Controller, Get } from "@nestjs/common";

export type HealthResponse = {
  service: "fangyuanli-api";
  status: "ok";
  version: string;
};

@Controller("health")
export class HealthController {
  @Get()
  getHealth(): HealthResponse {
    return {
      service: "fangyuanli-api",
      status: "ok",
      version: "0.1.0"
    };
  }
}
