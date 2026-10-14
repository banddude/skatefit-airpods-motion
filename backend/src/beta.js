// Read-only direct-install distribution endpoints. Signed IPA remains in private R2.
export const installHTML = "<!doctype html><html lang=\"en\"><head><meta charset=\"UTF-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><meta name=\"color-scheme\" content=\"dark\"><title>Install SkateFit Motion Lab Beta</title><style>body{font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif;background:#0e1823;color:#ecf4ff;margin:0;padding:34px 20px;line-height:1.55}main{max-width:580px;margin:0 auto}h1{font-size:28px;margin-bottom:6px}p{color:#a7c0d1}a.install{display:block;padding:17px 20px;background:#23bd9a;color:#071c21;text-align:center;font-size:18px;font-weight:700;text-decoration:none;border-radius:12px;margin:24px 0}a{color:#83e6d7}small{color:#93afbd}.panel{background:#1a2d3e;border-radius:12px;padding:18px 20px;margin-top:22px}li{margin:10px 0}</style></head><body><main><h1>SkateFit Motion Lab</h1><p>Standalone iPhone beta · v0.1.0 (9)</p><div class=\"panel\"><strong>Ready for this registered iPhone</strong><p>Use Safari on your iPhone to install. This direct-install beta is signed for Mike's registered iPhone; it does not replace the existing SkateFit app.</p></div><a class=\"install\" href=\"itms-services://?action=download-manifest&url=https%3A%2F%2Fskatefit-motion-lab.mikejshaffer.workers.dev%2Fbeta%2Fmanifest.plist\">Install beta on this iPhone</a><ol><li>Open this page in <strong>Safari</strong> on your iPhone.</li><li>Tap Install and confirm the iOS install prompt.</li><li>Find <strong>SkateFit Motion Lab</strong> on the Home Screen.</li><li>Pair AirPods Pro and grant Motion &amp; Fitness permission. Set the correct board-mounted AirPod side.</li><li>Keep the app foregrounded during calibration and testing. Use cellular data at the skatepark.</li></ol><p><a href=\"/\">Open live dashboard</a> · <a href=\"https://skatefit-motion-lab.mikejshaffer.workers.dev/beta/manifest.plist\">Inspect installation manifest</a></p><small>Experimental build. Board trick accuracy and off-ear sensor operation still require field testing. Public cloud telemetry is intentionally unauthenticated for development.</small></main></body></html>";
export const installManifest = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\"><dict>\n<key>items</key><array><dict>\n<key>assets</key><array>\n<dict><key>kind</key><string>software-package</string><key>url</key><string>https://skatefit-motion-lab.mikejshaffer.workers.dev/beta/SkateFitMotionLab.ipa</string></dict>\n<dict><key>kind</key><string>display-image</string><key>url</key><string>https://skatefit-motion-lab.mikejshaffer.workers.dev/beta/icon.png</string></dict>\n<dict><key>kind</key><string>full-size-image</string><key>url</key><string>https://skatefit-motion-lab.mikejshaffer.workers.dev/beta/icon.png</string></dict>\n</array>\n<key>metadata</key><dict>\n<key>bundle-identifier</key><string>com.banddude.skatefit.motionlab</string>\n<key>bundle-version</key><string>9</string>\n<key>kind</key><string>software</string>\n<key>title</key><string>SkateFit Motion Lab</string>\n</dict></dict></array>\n</dict></plist>\n";
const objects = Object.freeze({ipa:"ios/SkateFitMotionLab-0.1.0-9.ipa", icon:"ios/SkateFitMotionLab-icon.png"});
export async function getBetaAsset(request, env, kind) {
  const key = objects[kind];
  if (!key || !env.BETAS) return new Response("Beta storage unavailable", {status: 503});
  // Initial metadata request avoids guessing object size when honoring Range.
  const original = await env.BETAS.get(key);
  if (!original) return new Response("Beta asset not found", {status: 404});
  let object = original;
  let responseStatus = 200;
  let bytes = original.size;
  let contentRange = null;
  const rangeHeader = request.headers.get("range");
  if (rangeHeader && request.method === "GET") {
    const match = /^bytes=(\d+)-(\d*)$/.exec(rangeHeader);
    if (!match) return new Response(null, {
      status: 416, headers: {"content-range": "bytes */" + original.size}
    });
    const start = Number(match[1]);
    const end = match[2] === "" ? original.size - 1 : Number(match[2]);
    if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) ||
        start >= original.size || end < start || end >= original.size) {
      return new Response(null, {
        status: 416, headers: {"content-range": "bytes */" + original.size}
      });
    }
    bytes = end - start + 1;
    object = await env.BETAS.get(key, {range: {offset: start, length: bytes}});
    if (!object) return new Response("Beta asset not found", {status: 404});
    responseStatus = 206;
    contentRange = "bytes " + start + "-" + end + "/" + original.size;
  }
  const headers = new Headers();
  original.writeHttpMetadata(headers);
  headers.set("content-type", kind === "ipa" ? "application/octet-stream" : "image/png");
  headers.set("content-length", String(bytes));
  headers.set("accept-ranges", "bytes");
  headers.set("cache-control", "public, max-age=600");
  if (contentRange) headers.set("content-range", contentRange);
  if (kind === "ipa") headers.set("content-disposition", 'attachment; filename="SkateFitMotionLab.ipa"');
  return new Response(request.method === "HEAD" ? null : object.body, {
    status: responseStatus, headers
  });
}
