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

export async function readLimitedJSON(request: Request, maximum = 2048): Promise<Record<string, unknown>> {
  const reader = request.body?.getReader();
  if (!reader) throw new SyntaxError("JSON body required");
  const chunks: Uint8Array[] = [];
  let length = 0;
  while (true) {
    const chunk = await reader.read();
    if (chunk.done) break;
    length += chunk.value.byteLength;
    if (length > maximum) { await reader.cancel(); throw new RangeError("Request too large"); }
    chunks.push(chunk.value);
  }
  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  const body = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  if (!body || Array.isArray(body) || typeof body !== "object") throw new SyntaxError("JSON object required");
  return body;
}
