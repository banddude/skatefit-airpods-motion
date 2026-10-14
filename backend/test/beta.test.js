import test from "node:test";
import assert from "node:assert/strict";
import app from "../src/worker.js";
import { installHTML, installManifest } from "../src/beta.js";

test("iPhone installer exposes a Safari install link", () => {
  assert.match(installHTML, /itms-services:\/\/\?action=download-manifest/);
  assert.match(installHTML, /SkateFit Motion Lab/);
  assert.match(installHTML, /registered iPhone/);
});

test("OTA manifest uses the same bundle ID and hosted IPA as the archive", () => {
  assert.match(installManifest, /com\.banddude\.skatefit\.motionlab/);
  assert.match(installManifest, /<string>1<\/string>/);
  assert.match(installManifest, /https:\/\/skatefit-motion-lab\.mikejshaffer\.workers\.dev\/beta\/SkateFitMotionLab\.ipa/);
});

test("installation page and manifest return real HTTP documents", async () => {
  const env = {};
  const install = await app.fetch(new Request("https://example.test/install"), env);
  assert.equal(install.status, 200);
  assert.match(install.headers.get("content-type"), /text\/html/);
  assert.match(await install.text(), /Install beta on this iPhone/);

  const manifest = await app.fetch(new Request("https://example.test/beta/manifest.plist"), env);
  assert.equal(manifest.status, 200);
  assert.match(manifest.headers.get("content-type"), /application\/xml/);
  assert.match(await manifest.text(), /bundle-identifier/);
});

test("signed beta binary and icon stream through R2 over GET and HEAD", async () => {
  const calls = [];
  const env = {
    BETAS: {
      get: async key => {
        calls.push(key);
        const bytes = new Uint8Array([1, 2, 3, 4]);
        return {
          size: bytes.byteLength,
          writeHttpMetadata(h) { h.set("content-type", "application/octet-stream"); },
          body: new ReadableStream({
            start(c) { c.enqueue(bytes); c.close(); }
          })
        };
      }
    }
  };
  for (const method of ["GET", "HEAD"]) {
    const response = await app.fetch(new Request("https://example.test/beta/SkateFitMotionLab.ipa", {method}), env);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "application/octet-stream");
    assert.equal(Number(response.headers.get("content-length")), 4);
    assert.equal((await response.arrayBuffer()).byteLength, method === "GET" ? 4 : 0);
  }
  assert.deepEqual(calls, ["ios/SkateFitMotionLab-0.1.0-1.ipa", "ios/SkateFitMotionLab-0.1.0-1.ipa"]);
});
