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
  assert.match(installManifest, /<string>8<\/string>/);
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
  assert.deepEqual(calls, ["ios/SkateFitMotionLab-0.1.0-8.ipa", "ios/SkateFitMotionLab-0.1.0-8.ipa"]);
});

test("iOS partial downloads honor byte ranges and reject invalid requests", async () => {
  const bytes = new Uint8Array([10,20,30,40]);
  const env = {
    BETAS: {
      async get(key, options) {
        const data = options?.range
          ? bytes.slice(options.range.offset,
                        options.range.offset + options.range.length)
          : bytes;
        return {
          size: bytes.byteLength,
          writeHttpMetadata(h) { h.set("content-type","application/octet-stream"); },
          body: new ReadableStream({start(c) {c.enqueue(data);c.close();}})
        };
      }
    }
  };
  const ok = await app.fetch(new Request("https://example.test/beta/SkateFitMotionLab.ipa",{
    headers: {"Range":"bytes=1-2"}
  }), env);
  assert.equal(ok.status,206);
  assert.equal(ok.headers.get("content-range"),"bytes 1-2/4");
  assert.deepEqual([...new Uint8Array(await ok.arrayBuffer())],[20,30]);
  const rejected = await app.fetch(new Request("https://example.test/beta/SkateFitMotionLab.ipa",{
    headers: {"Range":"bytes=8-12"}
  }), env);
  assert.equal(rejected.status,416);
});

test("complete session stats cannot be attributed to a different session", async () => {
  const {validateSummary} = await import("../src/worker.js");
  const summary = {
    id:"test-session-valid-1234",
    startedAt:812345678.0, endedAt:812345700.0,
    boardSide:"right",calibrated:true,isSynthetic:false,
    csvFilename:"session-test-session-valid-1234.csv",
    stats:{boardSamples:100,phoneSamples:230,durationSeconds:22,
           possibleEvents:2},
    eventKinds:{"Possible manual":2}
  };
  assert.equal(validateSummary(summary,summary.id),true);
  assert.equal(validateSummary(summary,"other-session-1234"),false);
  assert.equal(validateSummary({...summary,stats:{...summary.stats,
    boardSamples:-1}},summary.id),false);
  assert.equal(validateSummary({...summary,startedAt:"yesterday"},summary.id),false);
});
