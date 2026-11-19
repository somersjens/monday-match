import * as x509 from "npm:@peculiar/x509@1.12.3";
import { compactVerify, decodeProtectedHeader, importX509 } from "npm:jose@5.9.6";

// Verifies an App Store signed transaction (StoreKit 2 `jwsRepresentation`)
// the way Apple's App Store Server Library does, without calling Apple:
// the x5c chain must end in Apple Root CA - G3 (pinned by fingerprint), each
// certificate must be signed by the next and valid when Apple signed the
// transaction, the leaf and intermediate must carry Apple's App Store
// receipt-signing OIDs, and the JWS must be signed by the leaf.

x509.cryptoProvider.set(crypto);

export const bundleID = "Hakketjak.monday-match";
export const products = [
  "lifetime_access", "lifetime_access_early_adopter", "lifetime_access_subscriber", "monthly_access",
] as const;
export type ProductID = typeof products[number];
// The store type each product must have; a misconfigured product grants nothing.
const productTypes: Record<ProductID, string> = {
  lifetime_access: "Non-Consumable",
  lifetime_access_early_adopter: "Non-Consumable",
  lifetime_access_subscriber: "Non-Consumable",
  monthly_access: "Auto-Renewable Subscription",
};

// SHA-256 of Apple Root CA - G3 (ECC P-384, valid until 2039-04-30), as listed
// at https://support.apple.com/en-us/105116.
export const appleRootG3SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";
const leafOID = "1.2.840.113635.100.6.11.1";
const intermediateOID = "1.2.840.113635.100.6.2.1";

export type Verified = {
  productID: ProductID;
  originalTransactionID: string;
  purchasedAt: Date;
  revokedAt: Date | null;
  /// The end of a subscription's period; null for one-time purchases.
  expiresAt: Date | null;
  environment: "sandbox" | "production";
};

export class Rejected extends Error {}

const hex = (buffer: ArrayBuffer) => [...new Uint8Array(buffer)].map((b) => b.toString(16).padStart(2, "0")).join("");
const der = (base64: string) => Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
const pem = (base64: string) => `-----BEGIN CERTIFICATE-----\n${base64.match(/.{1,64}/g)!.join("\n")}\n-----END CERTIFICATE-----`;

// The transaction's own fields, once the signature is known to be Apple's.
export function checkPayload(payload: Record<string, unknown>): Verified {
  if (payload.bundleId !== bundleID) throw new Rejected("Another app's transaction");
  const productID = payload.productId as ProductID;
  if (!products.includes(productID)) throw new Rejected("Unknown product");
  if (payload.type !== productTypes[productID]) throw new Rejected("Unexpected product type");
  const original = payload.originalTransactionId;
  if (typeof original !== "string" || !/^[0-9]{1,40}$/.test(original)) throw new Rejected("Bad transaction ID");
  const purchased = Number(payload.originalPurchaseDate);
  if (!Number.isFinite(purchased) || purchased <= 0) throw new Rejected("Bad purchase date");
  const revocation = payload.revocationDate == null ? null : Number(payload.revocationDate);
  const environment = payload.environment === "Production" ? "production"
    : payload.environment === "Sandbox" ? "sandbox" : null;
  if (!environment) throw new Rejected("Unsupported environment");
  let expiresAt: Date | null = null;
  if (productTypes[productID] === "Auto-Renewable Subscription") {
    const expires = Number(payload.expiresDate);
    if (!Number.isFinite(expires) || expires <= 0) throw new Rejected("Bad expiry date");
    expiresAt = new Date(expires);
  }
  return {
    productID, originalTransactionID: original, purchasedAt: new Date(purchased),
    revokedAt: revocation && Number.isFinite(revocation) ? new Date(revocation) : null, expiresAt, environment,
  };
}

export type VerifiedRenewal = {
  originalTransactionID: string;
  /// Whether the plan will be charged again at the end of its period.
  autoRenews: boolean;
};

// A subscription's signed renewal info (StoreKit's `renewalInfo`, or a
// notification's `signedRenewalInfo`), once the signature is known to be Apple's.
// It carries no bundle ID: the original transaction ID must match a purchase
// an account of this app recorded, which the database checks.
export function checkRenewal(payload: Record<string, unknown>): VerifiedRenewal {
  const productID = payload.productId as ProductID;
  if (productTypes[productID] !== "Auto-Renewable Subscription") throw new Rejected("Not this app's subscription");
  const original = payload.originalTransactionId;
  if (typeof original !== "string" || !/^[0-9]{1,40}$/.test(original)) throw new Rejected("Bad transaction ID");
  if (payload.autoRenewStatus !== 0 && payload.autoRenewStatus !== 1) throw new Rejected("No renewal status");
  if (payload.environment !== "Production" && payload.environment !== "Sandbox") {
    throw new Rejected("Unsupported environment");
  }
  return { originalTransactionID: original, autoRenews: payload.autoRenewStatus === 1 };
}

export async function verifyAppleRenewal(jws: string): Promise<VerifiedRenewal> {
  return checkRenewal(await verifyAppleJWS(jws));
}

export async function verifyAppleTransaction(jws: string): Promise<Verified> {
  return checkPayload(await verifyAppleJWS(jws));
}

// Any App Store signed payload: a transaction, or a server notification.
export async function verifyAppleJWS(jws: string): Promise<Record<string, unknown>> {
  if (typeof jws !== "string" || jws.length > 65_536 || jws.split(".").length !== 3) throw new Rejected("Not a JWS");
  const header = decodeProtectedHeader(jws);
  const chain = header.x5c;
  if (header.alg !== "ES256" || !Array.isArray(chain) || chain.length !== 3) throw new Rejected("Unexpected header");
  const [leaf, intermediate, root] = chain.map((item) => new x509.X509Certificate(der(item)));

  if (hex(await root.getThumbprint("SHA-256")) !== appleRootG3SHA256) throw new Rejected("Not Apple's root");
  if (!leaf.getExtension(leafOID) || !intermediate.getExtension(intermediateOID)) {
    throw new Rejected("Not an App Store signing certificate");
  }

  // Signature first, so the signing date can be trusted for the validity check.
  const { payload: bytes } = await compactVerify(jws, await importX509(pem(chain[0]), "ES256"));
  const payload = JSON.parse(new TextDecoder().decode(bytes));
  const signedAt = new Date(Number(payload.signedDate));
  if (Number.isNaN(signedAt.getTime())) throw new Rejected("No signing date");

  for (const [subject, issuer] of [[leaf, intermediate], [intermediate, root], [root, root]] as const) {
    const valid = await subject.verify({ publicKey: issuer.publicKey, date: signedAt });
    if (!valid) throw new Rejected("Broken certificate chain");
  }
  return payload;
}
