import { checkPayload, checkRenewal, Rejected, verifyAppleTransaction } from "./verify.ts";
const assert = (value: boolean, message = "Assertion failed") => { if (!value) throw new Error(message); };
const rejects = async (work: () => unknown) => {
  try { await work(); } catch (error) { assert(error instanceof Rejected || error instanceof Error); return; }
  throw new Error("Expected a rejection");
};

const payload = {
  bundleId: "Hakketjak.monday-match", productId: "lifetime_access", type: "Non-Consumable",
  originalTransactionId: "2000000123456789", originalPurchaseDate: 1763290000000, environment: "Production",
  signedDate: 1763290001000,
};

Deno.test("a lifetime purchase of this app is accepted", () => {
  const verified = checkPayload(payload);
  assert(verified.productID === "lifetime_access" && verified.environment === "production");
  assert(verified.purchasedAt.getTime() === 1763290000000 && verified.revokedAt === null);
  assert(checkPayload({ ...payload, revocationDate: 1763300000000 }).revokedAt !== null);
  assert(checkPayload({ ...payload, environment: "Sandbox" }).environment === "sandbox");
});

Deno.test("other apps, products, types and local Xcode tests are refused", async () => {
  await rejects(() => checkPayload({ ...payload, bundleId: "com.example.other" }));
  await rejects(() => checkPayload({ ...payload, productId: "coins" }));
  await rejects(() => checkPayload({ ...payload, type: "Consumable" }));
  await rejects(() => checkPayload({ ...payload, environment: "Xcode" }));
  await rejects(() => checkPayload({ ...payload, originalTransactionId: "1; drop table" }));
});

Deno.test("anything that isn't an Apple-signed JWS is refused", async () => {
  await rejects(() => verifyAppleTransaction("not.a.jws"));
  const unsigned = [{ alg: "none" }, payload, {}].map((part) => btoa(JSON.stringify(part))).join(".");
  await rejects(() => verifyAppleTransaction(unsigned));
});

Deno.test("the monthly plan needs its period end, lifetime products never have one", async () => {
  const monthly = { ...payload, productId: "monthly_access", type: "Auto-Renewable Subscription",
    expiresDate: 1765882000000 };
  const verified = checkPayload(monthly);
  assert(verified.productID === "monthly_access" && verified.expiresAt?.getTime() === 1765882000000);
  assert(checkPayload({ ...payload, productId: "lifetime_access_subscriber" }).expiresAt === null);
  await rejects(() => checkPayload({ ...monthly, expiresDate: undefined }));
  await rejects(() => checkPayload({ ...monthly, type: "Non-Consumable" }));
  await rejects(() => checkPayload({ ...payload, type: "Auto-Renewable Subscription" }));
});

Deno.test("a monthly plan's renewal info says whether it will be charged again", async () => {
  const renewal = { productId: "monthly_access", originalTransactionId: "2000000999", autoRenewStatus: 1,
    environment: "Sandbox", signedDate: 1763290001000 };
  assert(checkRenewal(renewal).autoRenews === true && checkRenewal(renewal).originalTransactionID === "2000000999");
  assert(checkRenewal({ ...renewal, autoRenewStatus: 0 }).autoRenews === false);
  await rejects(() => checkRenewal({ ...renewal, productId: "lifetime_access" }));
  await rejects(() => checkRenewal({ ...renewal, productId: "someone_elses_plan" }));
  await rejects(() => checkRenewal({ ...renewal, autoRenewStatus: undefined }));
  await rejects(() => checkRenewal({ ...renewal, environment: "Xcode" }));
});
