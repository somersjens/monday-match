import { passesVerification, uuid, readLimitedJSON } from "./policy.ts";
const assert = (value: boolean) => { if (!value) throw new Error("Assertion failed"); };
Deno.test("only server-confirmed liveness AND one matching profile face passes", () => {
  assert(passesVerification("SUCCEEDED", 99, 1, [98]));
  assert(!passesVerification("IN_PROGRESS", 99, 1, [98]));
  assert(!passesVerification("SUCCEEDED", 94.99, 1, [98]));
  assert(!passesVerification("SUCCEEDED", 99, 1, [94.99]));
  assert(!passesVerification("SUCCEEDED", 99, 2, [98]));
  assert(!passesVerification("SUCCEEDED", 99, 1, [98, 99]));
  assert(!passesVerification("SUCCEEDED", NaN, 1, [98]));
  assert(!passesVerification("SUCCEEDED", 99, 1, [Infinity]));
  assert(!passesVerification("FAILED", 100, 1, [100]));
});
Deno.test("malformed or absent session identifiers are rejected", () => {
  assert(uuid("a7fa0000-0000-4000-8000-000000000001"));
  assert(!uuid(null)); assert(!uuid({})); assert(!uuid("not-an-id"));
});

Deno.test("chunked bodies are bounded without trusting Content-Length", async () => {
  const valid = await readLimitedJSON(new Request("https://example.test", { method: "POST", body: '{"action":"start"}' }));
  assert(valid.action === "start");
  try {
    await readLimitedJSON(new Request("https://example.test", { method: "POST", body: "x".repeat(4096) }));
    throw new Error("Oversized body accepted");
  } catch (error) { assert(error instanceof RangeError); }
});
