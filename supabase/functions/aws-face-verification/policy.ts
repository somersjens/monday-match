export const REGION = "eu-west-1";
export const CONSENT = "2026-11-14.aws.v1";
export const MINIMUM_LIVENESS = 95;
export const MINIMUM_SIMILARITY = 95;
export function passesVerification(status: string | undefined, confidence: number | undefined,
  faces: number, similarities: number[]): boolean {
  return status === "SUCCEEDED" && Number.isFinite(confidence) && confidence! >= MINIMUM_LIVENESS &&
    confidence! <= 100 && faces === 1 && similarities.length === 1 &&
    Number.isFinite(similarities[0]) && similarities[0] >= MINIMUM_SIMILARITY && similarities[0] <= 100;
}
export function uuid(value: unknown): value is string {
  return typeof value === "string" && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}
