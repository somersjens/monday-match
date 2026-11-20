import * as x509 from "npm:@peculiar/x509@1.12.3";
import { decode } from "npm:cbor-x@1.6.0";
import { p256 } from "npm:@noble/curves@1.6.0/p256";
import { p384 } from "npm:@noble/curves@1.6.0/p384";

// Apple App Attest, checked as Apple describes in "Validating apps that
// connect to your server". Pure apart from WebCrypto digests, so it can be tested.
//
// The certificate chain is checked with @noble/curves, not WebCrypto: Apple's
// App Attestation CA signs the phone's certificate with a P-384 key and
// SHA-256, a pairing Deno's WebCrypto does not implement ("NotSupportedError:
// Not implemented", seen on the first real iPhone on 20 November 2026).

x509.cryptoProvider.set(crypto);

export const appID = "4283ACUG4Y.Hakketjak.monday-match"; // team ID + bundle ID
const nonceOID = "1.2.840.113635.100.8.2";
const development = new TextEncoder().encode("appattestdevelop");
const production = new Uint8Array([...new TextEncoder().encode("appattest"), 0, 0, 0, 0, 0, 0, 0]);

export class Rejected extends Error {}

export const sha256 = async (...parts: Uint8Array[]) => {
  const joined = new Uint8Array(parts.reduce((sum, part) => sum + part.length, 0));
  let offset = 0;
  for (const part of parts) { joined.set(part, offset); offset += part.length; }
  return new Uint8Array(await crypto.subtle.digest("SHA-256", joined));
};
export const fromBase64 = (text: string) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
export const toBase64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
export const equal = (a: Uint8Array, b: Uint8Array) => a.length === b.length && a.every((value, i) => value === b[i]);

// ===== Minimal DER reading: certificates, keys and signatures ==============

type DER = { tag: number; offset: number; start: number; end: number };

function derElement(bytes: Uint8Array, offset: number): DER {
  if (offset + 2 > bytes.length) throw new Rejected("Bad DER");
  const tag = bytes[offset];
  let length = bytes[offset + 1], start = offset + 2;
  if (length & 0x80) {
    const count = length & 0x7f;
    if (count === 0 || count > 4) throw new Rejected("Bad DER");
    length = 0;
    for (let i = 0; i < count; i++) length = length * 256 + bytes[start + i];
    start += count;
  }
  if (start + length > bytes.length) throw new Rejected("Bad DER");
  return { tag, offset, start, end: start + length };
}

function derChildren(bytes: Uint8Array, parent: DER): DER[] {
  const children: DER[] = [];
  for (let offset = parent.start; offset < parent.end;) {
    const child = derElement(bytes, offset);
    children.push(child);
    offset = child.end;
  }
  return children;
}

/** The uncompressed EC point inside a DER SubjectPublicKeyInfo. */
export function spkiPoint(spki: Uint8Array): Uint8Array {
  const [algorithm, bits] = derChildren(spki, derElement(spki, 0));
  if (algorithm?.tag !== 0x30 || bits?.tag !== 0x03 || spki[bits.start] !== 0) throw new Rejected("Bad public key");
  return spki.slice(bits.start + 1, bits.end);
}

// OBJECT IDENTIFIER contents of ecdsa-with-SHA256 and ecdsa-with-SHA384.
const ecdsaWithSHA256 = new Uint8Array([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02]);
const ecdsaWithSHA384 = new Uint8Array([0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03]);

/** Whether the holder of issuerPoint (P-256 or P-384) signed this DER certificate. */
export async function signedBy(certificate: Uint8Array, issuerPoint: Uint8Array): Promise<boolean> {
  const [tbs, algorithm, signature] = derChildren(certificate, derElement(certificate, 0));
  if (tbs?.tag !== 0x30 || algorithm?.tag !== 0x30 || signature?.tag !== 0x03) return false;
  const oid = derChildren(certificate, algorithm)[0];
  const value = certificate.slice(oid.start, oid.end);
  const hash = equal(value, ecdsaWithSHA256) ? "SHA-256" : equal(value, ecdsaWithSHA384) ? "SHA-384" : null;
  const curve = issuerPoint.length === 65 ? p256 : issuerPoint.length === 97 ? p384 : null;
  if (!hash || !curve || certificate[signature.start] !== 0) return false;
  const digest = new Uint8Array(await crypto.subtle.digest(hash, certificate.slice(tbs.offset, tbs.end)));
  try {
    // DER-encoded signature; NIST curves accept high-S signatures.
    return curve.verify(certificate.slice(signature.start + 1, signature.end), digest, issuerPoint, { lowS: false });
  } catch {
    return false;
  }
}

const within = (certificate: x509.X509Certificate, date: Date) =>
  date >= certificate.notBefore && date <= certificate.notAfter;

export type AuthData = {
  rpIDHash: Uint8Array; counter: number; aaguid?: Uint8Array; credentialID?: Uint8Array;
};

// WebAuthn authenticator data: rpIdHash(32) flags(1) counter(4) [aaguid(16) idLength(2) id ...].
// Only an attestation carries the credential part. An assertion's flags can
// still have the attested-data bit set (seen on an iPhone 17 Pro, 20 November
// 2026) while nothing follows the counter, so assertions read just the first 37 bytes.
export function parseAuthData(data: Uint8Array, withCredential = true): AuthData {
  if (data.length < 37) throw new Rejected("Authenticator data too short");
  const view = new DataView(data.buffer, data.byteOffset, data.byteLength);
  const result: AuthData = { rpIDHash: data.slice(0, 32), counter: view.getUint32(33) };
  if (withCredential && (data[32] & 0x40)) {
    if (data.length < 55) throw new Rejected("Attested credential data too short");
    const length = view.getUint16(53);
    if (data.length < 55 + length) throw new Rejected("Credential ID too short");
    result.aaguid = data.slice(37, 53);
    result.credentialID = data.slice(55, 55 + length);
  }
  return result;
}

// Root certificate: Apple publishes it at this address. It is fetched over
// TLS from apple.com and cached; the chain check below also requires it to
// be self-signed and named as Apple's App Attestation root.
const rootURL = "https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem";
let cachedRoot: x509.X509Certificate | null = null;
export async function appleRoot(): Promise<x509.X509Certificate> {
  if (cachedRoot) return cachedRoot;
  const response = await fetch(rootURL);
  if (!response.ok) throw new Error("Apple's App Attest root is unavailable");
  const root = new x509.X509Certificate(await response.text());
  const rootPoint = spkiPoint(new Uint8Array(root.publicKey.rawData));
  if (!root.subject.includes("CN=Apple App Attestation Root CA") ||
      !(await signedBy(new Uint8Array(root.rawData), rootPoint))) {
    throw new Error("Unexpected App Attest root");
  }
  cachedRoot = root;
  return root;
}

export type Attested = { publicKey: string; environment: "development" | "production" };

export async function verifyAttestation(input: {
  attestation: Uint8Array; challenge: Uint8Array; keyID: string; root: x509.X509Certificate; now?: Date;
}): Promise<Attested> {
  const object = decode(input.attestation) as {
    fmt?: string; attStmt?: { x5c?: Uint8Array[]; receipt?: Uint8Array }; authData?: Uint8Array;
  };
  if (object?.fmt !== "apple-appattest" || !object.authData || object.attStmt?.x5c?.length !== 2) {
    throw new Rejected("Not an App Attest object");
  }
  const [credentialDER, intermediateDER] = object.attStmt.x5c.map((item) => new Uint8Array(item));
  const [credential, intermediate] = [credentialDER, intermediateDER].map((item) => new x509.X509Certificate(item));
  const date = input.now ?? new Date();
  const intermediatePoint = spkiPoint(new Uint8Array(intermediate.publicKey.rawData));
  const rootPoint = spkiPoint(new Uint8Array(input.root.publicKey.rawData));
  if (!within(credential, date) || !within(intermediate, date) ||
      !(await signedBy(credentialDER, intermediatePoint)) || !(await signedBy(intermediateDER, rootPoint))) {
    throw new Rejected("Not certified by Apple");
  }

  // The certificate commits to this challenge and this authenticator data.
  const authData = new Uint8Array(object.authData);
  const nonce = await sha256(authData, await sha256(input.challenge));
  const extension = credential.getExtension(nonceOID);
  const value = extension ? new Uint8Array(extension.value) : new Uint8Array();
  if (value.length < 34 || value[value.length - 34] !== 0x04 || value[value.length - 33] !== 0x20 ||
      !equal(value.slice(-32), nonce)) {
    throw new Rejected("Challenge mismatch");
  }

  // The key ID is the hash of the certified public key (the uncompressed point).
  const point = spkiPoint(new Uint8Array(credential.publicKey.rawData));
  const keyID = fromBase64(input.keyID);
  if (!equal(await sha256(point), keyID)) throw new Rejected("Key ID mismatch");

  const parsed = parseAuthData(authData);
  if (!equal(parsed.rpIDHash, await sha256(new TextEncoder().encode(appID)))) throw new Rejected("Another app");
  if (parsed.counter !== 0) throw new Rejected("Counter must start at zero");
  const environment = parsed.aaguid && equal(parsed.aaguid, production) ? "production"
    : parsed.aaguid && equal(parsed.aaguid, development) ? "development" : null;
  if (!environment) throw new Rejected("Unknown App Attest environment");
  if (!parsed.credentialID || !equal(parsed.credentialID, keyID)) throw new Rejected("Credential mismatch");

  return { publicKey: toBase64(new Uint8Array(credential.publicKey.rawData)), environment };
}

// ECDSA signatures arrive DER-encoded; WebCrypto wants r || s.
export function derToRaw(signature: Uint8Array): Uint8Array {
  let offset = 2;
  if (signature[0] !== 0x30) throw new Rejected("Bad signature");
  if (signature[1] & 0x80) offset += signature[1] & 0x7f;
  const read = () => {
    if (signature[offset] !== 0x02) throw new Rejected("Bad signature");
    const length = signature[offset + 1];
    let value = signature.slice(offset + 2, offset + 2 + length);
    offset += 2 + length;
    while (value.length > 32 && value[0] === 0) value = value.slice(1);
    if (value.length > 32) throw new Rejected("Bad signature");
    const padded = new Uint8Array(32);
    padded.set(value, 32 - value.length);
    return padded;
  };
  const r = read(), s = read();
  return new Uint8Array([...r, ...s]);
}

export async function verifyAssertion(input: {
  assertion: Uint8Array; clientData: Uint8Array; publicKey: string; signCount: number;
}): Promise<number> {
  const object = decode(input.assertion) as { signature?: Uint8Array; authenticatorData?: Uint8Array };
  if (!object?.signature || !object.authenticatorData) throw new Rejected("Not an assertion");
  const authData = new Uint8Array(object.authenticatorData);
  const nonce = await sha256(authData, await sha256(input.clientData));
  const key = await crypto.subtle.importKey("spki", fromBase64(input.publicKey),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  const valid = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key,
    derToRaw(new Uint8Array(object.signature)), nonce);
  if (!valid) throw new Rejected("Bad signature");
  const parsed = parseAuthData(authData, false);
  if (!equal(parsed.rpIDHash, await sha256(new TextEncoder().encode(appID)))) throw new Rejected("Another app");
  if (parsed.counter <= input.signCount) throw new Rejected("Replayed assertion");
  return parsed.counter;
}
