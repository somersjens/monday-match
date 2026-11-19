import { derToRaw, parseAuthData, Rejected, sha256, verifyAssertion } from "./verify.ts";
import { encode } from "npm:cbor-x@1.6.0";
const assert = (value: boolean, message = "Assertion failed") => { if (!value) throw new Error(message); };

const appID = "4283ACUG4Y.Hakketjak.monday-match";

// Authenticator data the way the Secure Enclave builds it for an assertion.
async function authData(counter: number, id = appID) {
  const data = new Uint8Array(37);
  data.set(await sha256(new TextEncoder().encode(id)), 0);
  new DataView(data.buffer).setUint32(33, counter);
  return data;
}

// DER-encodes a raw r || s signature like CryptoKit's derRepresentation.
function rawToDer(raw: Uint8Array) {
  const part = (bytes: Uint8Array) => {
    let value = bytes; while (value.length > 1 && value[0] === 0 && !(value[1] & 0x80)) value = value.slice(1);
    if (value[0] & 0x80) value = new Uint8Array([0, ...value]);
    return [0x02, value.length, ...value];
  };
  const body = [...part(raw.slice(0, 32)), ...part(raw.slice(32))];
  return new Uint8Array([0x30, body.length, ...body]);
}

async function signedAssertion(counter: number, clientData: Uint8Array, id = appID) {
  const pair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const data = await authData(counter, id);
  const nonce = await sha256(data, await sha256(clientData));
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, pair.privateKey, nonce));
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", pair.publicKey));
  return { assertion: encode({ signature: rawToDer(raw), authenticatorData: data }),
           publicKey: btoa(String.fromCharCode(...spki)) };
}

Deno.test("a signed assertion with a newer counter is accepted", async () => {
  const clientData = new TextEncoder().encode('{"challenge":"x","photo_id":"y","purpose":"photo_verification"}');
  const { assertion, publicKey } = await signedAssertion(3, clientData);
  assert(await verifyAssertion({ assertion, clientData, publicKey, signCount: 2 }) === 3);
});

Deno.test("replays, other client data and other apps are refused", async () => {
  const clientData = new TextEncoder().encode("{}");
  const { assertion, publicKey } = await signedAssertion(3, clientData);
  let refused = 0;
  for (const attempt of [
    () => verifyAssertion({ assertion, clientData, publicKey, signCount: 3 }),
    () => verifyAssertion({ assertion, clientData: new TextEncoder().encode("{ }"), publicKey, signCount: 0 }),
  ]) { try { await attempt(); } catch (error) { if (error instanceof Rejected) refused++; } }
  const other = await signedAssertion(5, clientData, "TEAM.other.app");
  try { await verifyAssertion({ ...other, clientData, signCount: 0 }); } catch (error) { if (error instanceof Rejected) refused++; }
  assert(refused === 3);
});

Deno.test("authenticator data and DER signatures are parsed strictly", async () => {
  const parsed = parseAuthData(await authData(7));
  assert(parsed.counter === 7 && parsed.credentialID === undefined);
  let refused = false;
  try { parseAuthData(new Uint8Array(10)); } catch (error) { refused = error instanceof Rejected; }
  assert(refused);
  const raw = new Uint8Array(64).map((_, i) => i + 1);
  assert(derToRaw(rawToDer(raw)).every((value, i) => value === raw[i]));
});
