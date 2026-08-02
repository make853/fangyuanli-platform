import type { Gcj02Point } from "../geo/location-context.js";

const EARTH_RADIUS_METERS = 6_371_008.8;

export function distanceMeters(a: Gcj02Point, b: Gcj02Point): number {
  const radians = Math.PI / 180;
  const latitudeDelta = (b.latitude - a.latitude) * radians;
  const longitudeDelta = (b.longitude - a.longitude) * radians;
  const latitudeA = a.latitude * radians;
  const latitudeB = b.latitude * radians;
  const haversine =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(latitudeA) *
      Math.cos(latitudeB) *
      Math.sin(longitudeDelta / 2) ** 2;
  return Math.round(
    2 * EARTH_RADIUS_METERS * Math.asin(Math.min(1, Math.sqrt(haversine)))
  );
}

export function displayDistance(meters: number): string {
  if (meters < 1000) return `约${meters}米`;
  const kilometers = meters < 10_000 ? (meters / 1000).toFixed(1) : Math.round(meters / 1000);
  return `约${kilometers}公里`;
}
