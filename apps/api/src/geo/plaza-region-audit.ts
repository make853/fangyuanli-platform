import type { Gcj02Point } from "./location-context.js";
import type {
  PlazaCell,
  PlazaGridVersion
} from "./plaza-context.types.js";
import { PlazaGridProjector } from "./plaza-grid-projector.js";
import type {
  PlazaNamingKind,
  PlazaNamingSource
} from "./plaza-naming.provider.js";

export type PlazaRegionAuditEntryInput = PlazaCell & {
  plazaId: string;
  name: string;
  namingSource: PlazaNamingSource | "neutral";
  namingKind: PlazaNamingKind | null;
  namingPoint: Gcj02Point | null;
};

export type PlazaRegionAuditInput = {
  generatedAt: Date;
  version: PlazaGridVersion;
  anchorPoint: Gcj02Point;
  plazas: PlazaRegionAuditEntryInput[];
};

export type PlazaRegionAuditEntry = PlazaRegionAuditEntryInput & {
  relation: "main" | "adjacent";
  direction: string;
  landmarkInsideCell: boolean | null;
  landmarkDistanceMeters: number | null;
};

export type PlazaRegionAuditReport = {
  generatedAt: Date;
  version: PlazaGridVersion;
  anchorPoint: Gcj02Point;
  plazas: PlazaRegionAuditEntry[];
  allNamedLandmarksInsideOwnCell: boolean;
};

export class PlazaRegionAuditor {
  constructor(private readonly projector: PlazaGridProjector) {}

  build(input: PlazaRegionAuditInput): PlazaRegionAuditReport {
    if (input.plazas.length !== 4) {
      throw new Error("A plaza region audit requires exactly four plazas");
    }
    const uniqueCells = new Set(
      input.plazas.map((plaza) => `${plaza.gridX}:${plaza.gridY}`)
    );
    if (uniqueCells.size !== input.plazas.length) {
      throw new Error("A plaza region audit requires four distinct cells");
    }

    const main = input.plazas[0];
    const plazas = input.plazas.map((plaza, index) => {
      const landmarkInsideCell = plaza.namingPoint
        ? this.projector.contains(plaza, input.version, plaza.namingPoint)
        : null;
      return {
        ...plaza,
        relation: index === 0 ? "main" : "adjacent",
        direction: index === 0 ? "当前位置" : this.direction(main, plaza),
        landmarkInsideCell,
        landmarkDistanceMeters: plaza.namingPoint
          ? Math.round(
              this.projector.distanceMeters(input.anchorPoint, plaza.namingPoint)
            )
          : null
      } satisfies PlazaRegionAuditEntry;
    });

    return {
      generatedAt: input.generatedAt,
      version: input.version,
      anchorPoint: input.anchorPoint,
      plazas,
      allNamedLandmarksInsideOwnCell: plazas.every(
        (plaza) => plaza.landmarkInsideCell !== false
      )
    };
  }

  renderSvg(report: PlazaRegionAuditReport): string {
    const width = 1080;
    const height = 920;
    const mapLeft = 70;
    const mapTop = 140;
    const mapSize = 600;
    const minimumGridX = Math.min(...report.plazas.map((plaza) => plaza.gridX));
    const maximumGridX = Math.max(...report.plazas.map((plaza) => plaza.gridX));
    const minimumGridY = Math.min(...report.plazas.map((plaza) => plaza.gridY));
    const maximumGridY = Math.max(...report.plazas.map((plaza) => plaza.gridY));
    const columns = maximumGridX - minimumGridX + 1;
    const rows = maximumGridY - minimumGridY + 1;
    const cellWidth = mapSize / columns;
    const cellHeight = mapSize / rows;
    const main = report.plazas[0];
    const anchorPosition = this.projector.positionWithinCell(
      report.anchorPoint,
      main,
      report.version
    );
    const anchorX =
      mapLeft + (main.gridX - minimumGridX + anchorPosition.xFraction) * cellWidth;
    const anchorY =
      mapTop +
      (maximumGridY - main.gridY + 1 - anchorPosition.yFraction) * cellHeight;

    const cells = report.plazas
      .map((plaza, index) => {
        const x = mapLeft + (plaza.gridX - minimumGridX) * cellWidth;
        const y = mapTop + (maximumGridY - plaza.gridY) * cellHeight;
        const state = plaza.landmarkInsideCell;
        const fill = index === 0 ? "#D9F1E7" : "#F7FAF8";
        const border = state === false ? "#D04A4A" : "#8FA99E";
        const status =
          state === true ? "地标在本格内" : state === false ? "地标越界" : "中性名称";
        const statusColor =
          state === true ? "#087E5B" : state === false ? "#C53636" : "#737D78";
        const marker = plaza.namingPoint
          ? this.landmarkMarker({
              plaza,
              x,
              y,
              cellWidth,
              cellHeight,
              version: report.version
            })
          : "";
        return `
          <g>
            <rect x="${x}" y="${y}" width="${cellWidth}" height="${cellHeight}"
              rx="22" fill="${fill}" stroke="${border}" stroke-width="3" />
            <text x="${x + 22}" y="${y + 38}" class="relation">${this.escape(
              index === 0 ? "主广场" : `相邻 · ${plaza.direction}`
            )}</text>
            <text x="${x + 22}" y="${y + 76}" class="name">${this.escape(
              this.truncate(plaza.name, 13)
            )}</text>
            <text x="${x + 22}" y="${y + cellHeight - 28}" class="status"
              fill="${statusColor}">${status}</text>
            ${marker}
          </g>`;
      })
      .join("");

    const list = report.plazas
      .map((plaza, index) => {
        const y = 785 + index * 30;
        const distance =
          plaza.landmarkDistanceMeters === null
            ? "无地标坐标"
            : `距用户约 ${plaza.landmarkDistanceMeters} 米`;
        const status =
          plaza.landmarkInsideCell === true
            ? "通过"
            : plaza.landmarkInsideCell === false
              ? "越界"
              : "中性兜底";
        return `<text x="70" y="${y}" class="audit-row">${index + 1}. ${this.escape(
          plaza.name
        )} · ${this.escape(plaza.direction)} · ${this.escape(distance)} · ${status}</text>`;
      })
      .join("");

    const overallColor = report.allNamedLandmarksInsideOwnCell
      ? "#087E5B"
      : "#C53636";
    const overallText = report.allNamedLandmarksInsideOwnCell
      ? "归属检查通过：所有已命名地标均位于各自方格内"
      : "归属检查失败：存在跨方格地标";

    return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}">
  <rect width="100%" height="100%" fill="#F4F7F5" />
  <style>
    text { font-family: -apple-system, BlinkMacSystemFont, "PingFang SC", "Noto Sans CJK SC", sans-serif; fill: #17221E; }
    .title { font-size: 34px; font-weight: 700; }
    .subtitle { font-size: 18px; fill: #64706B; }
    .relation { font-size: 18px; font-weight: 600; fill: #64706B; }
    .name { font-size: 25px; font-weight: 700; }
    .status { font-size: 17px; font-weight: 600; }
    .legend { font-size: 17px; fill: #59645F; }
    .overall { font-size: 21px; font-weight: 700; }
    .audit-row { font-size: 17px; fill: #3F4B46; }
  </style>
  <text x="70" y="62" class="title">方圆里 · 四广场地理审计</text>
  <text x="70" y="98" class="subtitle">网格版本 ${report.version.version} · 单格 ${
    report.version.sideLengthMeters / 1000
  } 公里 × ${report.version.sideLengthMeters / 1000} 公里 · 生成于 ${this.escape(
    report.generatedAt.toISOString()
  )}</text>
  ${cells}
  <circle cx="${anchorX}" cy="${anchorY}" r="13" fill="#111F19" stroke="#FFFFFF" stroke-width="5" />
  <text x="${anchorX + 18}" y="${anchorY - 14}" class="legend">你的位置</text>
  <g transform="translate(710 170)">
    <text x="0" y="0" class="title" font-size="25">图例</text>
    <circle cx="8" cy="42" r="8" fill="#111F19" /><text x="28" y="48" class="legend">用户锚点</text>
    <circle cx="8" cy="82" r="8" fill="#087E5B" /><text x="28" y="88" class="legend">本格命名地标</text>
    <circle cx="8" cy="122" r="8" fill="#C53636" /><text x="28" y="128" class="legend">错误的跨格地标</text>
    <text x="0" y="184" class="legend">方格只按网格坐标绘制，</text>
    <text x="0" y="212" class="legend">不展示道路与用户精确坐标。</text>
  </g>
  <text x="710" y="480" class="overall" fill="${overallColor}">${overallText}</text>
  <text x="70" y="754" class="subtitle">逐格结果</text>
  ${list}
</svg>`;
  }

  private landmarkMarker(input: {
    plaza: PlazaRegionAuditEntry;
    x: number;
    y: number;
    cellWidth: number;
    cellHeight: number;
    version: PlazaGridVersion;
  }): string {
    const point = input.plaza.namingPoint;
    if (!point) return "";
    const position = this.projector.positionWithinCell(
      point,
      input.plaza,
      input.version
    );
    const markerX = input.x + this.clamp(position.xFraction, 0.04, 0.96) * input.cellWidth;
    const markerY =
      input.y + (1 - this.clamp(position.yFraction, 0.04, 0.96)) * input.cellHeight;
    const color = input.plaza.landmarkInsideCell === false ? "#C53636" : "#087E5B";
    return `<circle cx="${markerX}" cy="${markerY}" r="10" fill="${color}" stroke="#FFFFFF" stroke-width="4" />`;
  }

  private direction(origin: PlazaCell, target: PlazaCell): string {
    const x = Math.sign(target.gridX - origin.gridX);
    const y = Math.sign(target.gridY - origin.gridY);
    const directions = new Map([
      ["0:1", "北"],
      ["1:1", "东北"],
      ["1:0", "东"],
      ["1:-1", "东南"],
      ["0:-1", "南"],
      ["-1:-1", "西南"],
      ["-1:0", "西"],
      ["-1:1", "西北"]
    ]);
    return directions.get(`${x}:${y}`) ?? "相邻";
  }

  private truncate(value: string, maximumCharacters: number): string {
    const characters = [...value];
    return characters.length <= maximumCharacters
      ? value
      : `${characters.slice(0, maximumCharacters - 1).join("")}…`;
  }

  private clamp(value: number, minimum: number, maximum: number): number {
    return Math.max(minimum, Math.min(maximum, value));
  }

  private escape(value: string): string {
    return value
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&apos;");
  }
}
