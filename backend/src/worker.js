import dashboard from "./dashboard.js";
import { installHTML, installManifest, getBetaAsset } from "./beta.js";
import { DEFAULT_RULES, validateRules, reprocessSamples } from "./detector.js";

const json = (value, status=200) => new Response(JSON.stringify(value), {
  status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" }
});
function failure(message, status=400) { return json({ok:false,error:message},status); }
function validId(id) { return typeof id==="string" && /^[a-zA-Z0-9_-]{8,100}$/.test(id); }
function goodNumber(x) { return typeof x==="number" && Number.isFinite(x); }
function isVector(x) { return x && ["x","y","z"].every(k=>goodNumber(x[k])); }
function validSample(s) {
  return s && ["headphone","phone","simulation"].includes(s.source)
    && typeof s.sensorLocation==="string" && s.sensorLocation.length<=20
    && goodNumber(s.hostUptime) && goodNumber(s.deviceTimestamp)
    && isVector(s.gravity) && isVector(s.acceleration) && isVector(s.rotationRate);
}
function validCalibration(c) {
  return c && isVector(c.flat)&&isVector(c.tail)&&isVector(c.nose);
}
export function validateSummary(summary, sessionId) {
  if (!summary || typeof summary!=="object" || Array.isArray(summary)
      || summary.id!==sessionId || !validId(summary.id)
      || !goodNumber(summary.startedAt)
      || (summary.endedAt!=null && !goodNumber(summary.endedAt))
      || typeof summary.boardSide!=="string"
      || !["left","right"].includes(summary.boardSide)
      || typeof summary.calibrated!=="boolean"
      || typeof summary.isSynthetic!=="boolean"
      || !summary.stats || typeof summary.stats!=="object"
      || !Number.isSafeInteger(summary.stats.boardSamples)
      || summary.stats.boardSamples<0
      || !Number.isSafeInteger(summary.stats.phoneSamples)
      || summary.stats.phoneSamples<0
      || !goodNumber(summary.stats.durationSeconds)
      || summary.stats.durationSeconds<0
      || !Number.isSafeInteger(summary.stats.possibleEvents)
      || summary.stats.possibleEvents<0
      || typeof summary.csvFilename!=="string"
      || summary.csvFilename.length>160
      || !summary.eventKinds || typeof summary.eventKinds!=="object"
      || JSON.stringify(summary).length>10000) return false;
  return true;
}

function cors(response) {
  const h=new Headers(response.headers);
  h.set("access-control-allow-origin","*");
  h.set("access-control-allow-methods","GET, POST, PUT, OPTIONS");
  h.set("access-control-allow-headers","Content-Type");
  return new Response(response.body,{status:response.status,headers:h});
}
async function config(db) {
  const row=await db.prepare("SELECT version,rules_json,updated_at FROM settings WHERE id=1").first();
  if(!row)return {version:0,rules:DEFAULT_RULES,updatedAt:null};
  return {version:row.version,rules:validateRules(JSON.parse(row.rules_json)),updatedAt:row.updated_at};
}
async function readBody(request) {
  if(Number(request.headers.get("content-length")||0)>240000)throw new Error("Payload is too large (240KB max).");
  const text=await request.text();
  if(text.length>240000)throw new Error("Payload is too large (240KB max).");
  return JSON.parse(text);
}
async function ingest(request,db) {
  const data=await readBody(request);
  if(!validId(data.sessionId))return failure("Invalid session ID.");
  if(!validId(data.batchId))return failure("Invalid batch ID.");
  const samples=data.samples;
  const events=Array.isArray(data.events)?data.events:[];
  const summary=data.summary??null;
  if(summary!==null && !validateSummary(summary,data.sessionId))
    return failure("Invalid session summary.");
  if(!Array.isArray(samples)||samples.length>180||samples.some(s=>!validSample(s)))
    return failure("samples must contain up to 180 valid readings.");
  if(samples.length===0&&events.length===0&&!summary)return failure("Nothing to record.");
  if(events.length>30)return failure("Maximum 30 events per batch.");
  if(data.calibration!==undefined && !validCalibration(data.calibration))
    return failure("Invalid calibration.");
  const diagnostics=data.diagnostics;
  if(diagnostics!==undefined && diagnostics!==null){
    if(!diagnostics || typeof diagnostics!=="object" || Array.isArray(diagnostics)
      || typeof diagnostics.headphoneAvailable!=="boolean"
      || typeof diagnostics.headphoneActive!=="boolean"
      || !["Authorized","Not yet requested","Restricted","Unknown authorization",
            "Denied. Enable Motion & Fitness access in Settings."].includes(diagnostics.permission)
      || typeof diagnostics.detectedSide!=="string"
      || !["none","left","right","default"].includes(diagnostics.detectedSide)
      || !["boardReadings","headphoneReadings","phoneReadings"].every(
         key=>Number.isSafeInteger(diagnostics[key]) && diagnostics[key]>=0)
      || typeof diagnostics.message!=="string"
      || diagnostics.message.length>500
      || (diagnostics.audioOutput!=null &&
          (typeof diagnostics.audioOutput!=="string" || diagnostics.audioOutput.length>240))
      || (diagnostics.audioWakeStatus!=null &&
          (typeof diagnostics.audioWakeStatus!=="string" || diagnostics.audioWakeStatus.length>500)))
      return failure("Invalid sensor diagnostics.");
  }
  const existing=await db.prepare("SELECT id FROM batches WHERE batch_id=?").bind(data.batchId).first();
  if(existing)return json({ok:true,duplicate:true,accepted:0});

  const calibrationString=data.calibration?JSON.stringify(data.calibration):null;
  const diagnosticString=diagnostics?JSON.stringify(diagnostics):null;
  const summaryString=summary?JSON.stringify(summary):null;
  const side=data.preferredSide==="right"?"right":"left";
  const device=typeof data.device==="string"?data.device.slice(0,80):"iPhone";
  const latest=samples.length?Math.max(...samples.map(s=>s.hostUptime)):0;
  const mutations=[
    db.prepare("INSERT OR IGNORE INTO sessions (id,device,calibration_json,preferred_side) VALUES (?,?,?,?)")
      .bind(data.sessionId,device,calibrationString,side),
    db.prepare("INSERT INTO batches (session_id,batch_id,sample_count,payload) VALUES (?,?,?,?)")
      .bind(data.sessionId,data.batchId,samples.length,JSON.stringify(samples)),
    db.prepare("UPDATE sessions SET last_seen=CURRENT_TIMESTAMP, last_uptime=MAX(last_uptime,?),sample_count=sample_count+?, event_count=event_count+?, calibration_json=COALESCE(?,calibration_json),diagnostics_json=COALESCE(?,diagnostics_json),summary_json=COALESCE(?,summary_json),preferred_side=? WHERE id=?")
      .bind(latest,samples.length,events.length,calibrationString,diagnosticString,summaryString,side,data.sessionId)
  ];
  for(const e of events){
    if(typeof e.kind!=="string"||e.kind.length>100||!goodNumber(e.start)||!goodNumber(e.end))
      return failure("Invalid event.");
    mutations.push(db.prepare("INSERT INTO events(session_id,kind,event_start,event_end,confidence,detail,event_source) VALUES (?,?,?,?,?,?,?)")
      .bind(data.sessionId,e.kind,e.start,e.end,
        goodNumber(e.confidence)?Math.max(0,Math.min(1,e.confidence)):0,
        String(e.detail||"").slice(0,2000),"phone"));
  }
  await db.batch(mutations);
  return json({ok:true,accepted:samples.length,events:events.length,sessionId:data.sessionId});
}
async function latestSession(db,id){
  const session=await db.prepare("SELECT * FROM sessions WHERE id=?").bind(id).first();
  if(!session)return failure("No such session.",404);
  const [batches,events,labels]=await Promise.all([
    db.prepare("SELECT id,arrived_at,sample_count,payload FROM batches WHERE session_id=? ORDER BY id DESC LIMIT 3").bind(id).all(),
    db.prepare("SELECT * FROM events WHERE session_id=? ORDER BY id DESC LIMIT 60").bind(id).all(),
    db.prepare("SELECT * FROM labels WHERE session_id=? ORDER BY id DESC LIMIT 60").bind(id).all()
  ]);
  const latest=batches.results.flatMap(b=>JSON.parse(b.payload)).sort((a,b)=>a.hostUptime-b.hostUptime);
  return json({ok:true,session,latestSamples:latest.slice(-160),events:events.results,labels:labels.results});
}
async function reprocess(request,db) {
  const body=await readBody(request);
  if(!validId(body.sessionId))return failure("Invalid session ID.");
  const session=await db.prepare("SELECT * FROM sessions WHERE id=?").bind(body.sessionId).first();
  if(!session)return failure("No such session.",404);
  if(!session.calibration_json)return failure("This session has no three-pose calibration.",422);
  // Last 150 chunks (typically 2-3 minutes). Do not load unbounded session data.
  const batches=await db.prepare("SELECT payload FROM batches WHERE session_id=? ORDER BY id DESC LIMIT 150").bind(body.sessionId).all();
  const readings=batches.results.reverse().flatMap(b=>JSON.parse(b.payload));
  const rules=(await config(db)).rules;
  const {events,error}=reprocessSamples(readings,JSON.parse(session.calibration_json),
    rules,session.preferred_side);
  if(error)return failure(error,422);
  const queries=[db.prepare("DELETE FROM events WHERE session_id=? AND event_source='server'")
    .bind(body.sessionId)];
  for(const e of events.slice(-500)){
    queries.push(db.prepare("INSERT INTO events(session_id,kind,event_start,event_end,confidence,detail,event_source) VALUES(?,?,?,?,?,?,?)")
      .bind(body.sessionId,e.kind,e.start,e.end,e.confidence,e.detail,"server"));
  }
  await db.batch(queries);
  return json({ok:true,scannedSamples:readings.length,events:events.length,truncated:batches.results.length>=150});
}
async function csvExport(db,id){
  const session=await db.prepare("SELECT id FROM sessions WHERE id=?").bind(id).first();
  if(!session)return failure("No such session.",404);
  const columns=["hostUptime","deviceTimestamp","source","sensorLocation",
    "gravity.x","gravity.y","gravity.z","acceleration.x","acceleration.y","acceleration.z",
    "rotationRate.x","rotationRate.y","rotationRate.z","pitch","roll","yaw",
    "quaternion.w","quaternion.x","quaternion.y","quaternion.z"];
  const encoder=new TextEncoder();
  // Paginate and stream every batch instead of silently truncating sessions.
  const stream=new ReadableStream({
    async start(controller) {
      try {
        controller.enqueue(encoder.encode(columns.join(",")+"\n"));
        let lastId=0;
        for (;;) {
          const rows=await db.prepare(
            "SELECT id,payload FROM batches WHERE session_id=? AND id>? ORDER BY id ASC LIMIT 60"
          ).bind(id,lastId).all();
          if(!rows.results.length)break;
          let chunk="";
          for(const batch of rows.results){
            for(const s of JSON.parse(batch.payload)){
              const values=columns.map(key=>key.split(".").reduce((x,part)=>x?.[part],s));
              chunk+=values.map(v=>v===undefined||v===null?"":String(v)).join(",")+"\n";
            }
            lastId=batch.id;
          }
          controller.enqueue(encoder.encode(chunk));
        }
        controller.close();
      } catch(error) {
        console.error("CSV export error",error);
        controller.error(error);
      }
    }
  });
  return new Response(stream,{headers:{
    "content-type":"text/csv; charset=utf-8",
    "content-disposition":'attachment; filename="skatefit-'+id+'.csv"',
    "cache-control":"no-store"
  }});
}

async function handle(request,env) {
  const u=new URL(request.url),path=u.pathname,method=request.method;
  if(method==="OPTIONS")return new Response(null,{status:204});
  if((method==="GET"||method==="HEAD")&&path==="/install") {
    return new Response(method==="HEAD"?null:installHTML,{
      headers:{"content-type":"text/html; charset=utf-8","cache-control":"no-store"}
    });
  }
  if((method==="GET"||method==="HEAD")&&path==="/beta/manifest.plist") {
    return new Response(method==="HEAD"?null:installManifest,{
      headers:{"content-type":"application/xml; charset=utf-8","cache-control":"no-store"}
    });
  }
  if((method==="GET"||method==="HEAD")&&path==="/beta/SkateFitMotionLab.ipa")
    return getBetaAsset(request,env,"ipa");
  if((method==="GET"||method==="HEAD")&&path==="/beta/icon.png")
    return getBetaAsset(request,env,"icon");
  if(method==="HEAD"&&(path==="/"||path==="/health")){
    return new Response(null,{status:200,headers:{
      "content-type":path==="/"?"text/html; charset=utf-8":"application/json; charset=utf-8"
    }});
  }
  if(method==="GET"&&path==="/")return new Response(dashboard,{
    headers:{"content-type":"text/html; charset=utf-8","cache-control":"no-store"}
  });
  if(method==="GET"&&path==="/health")return json({ok:true,service:"SkateFit Motion Lab",at:new Date().toISOString()});
  if(method==="GET"&&path==="/api/config")return json({ok:true,...await config(env.DB)});
  if(method==="PUT"&&path==="/api/config"){
    const body=await readBody(request);
    if(!body.rules||typeof body.rules!=="object"||Array.isArray(body.rules)){
      return failure("rules must be an object.");
    }
    // Partial remote patches preserve other custom tuning values.
    const current=(await config(env.DB)).rules;
    const rules=validateRules({...current,...body.rules});
    await env.DB.prepare("UPDATE settings SET version=version+1,rules_json=?,updated_at=CURRENT_TIMESTAMP WHERE id=1")
      .bind(JSON.stringify(rules)).run();
    return json({ok:true,...await config(env.DB)});
  }
  if(method==="POST"&&path==="/api/ingest")return ingest(request,env.DB);
  if(method==="GET"&&path==="/api/sessions"){
    const rows=await env.DB.prepare("SELECT id,device,started_at,last_seen,sample_count,event_count,last_uptime,calibration_json IS NOT NULL AS calibrated FROM sessions ORDER BY last_seen DESC LIMIT 40").all();
    return json({ok:true,sessions:rows.results});
  }
  if(method==="POST"&&path==="/api/reprocess")return reprocess(request,env.DB);
  if(method==="POST"&&path==="/api/labels"){
    const body=await readBody(request);
    if(!validId(body.sessionId)||typeof body.label!=="string"||body.label.length>80)
      return failure("Invalid session or label.");
    await env.DB.prepare("INSERT INTO labels(session_id,event_id,label,note) VALUES (?,?,?,?)")
      .bind(body.sessionId,Number.isInteger(body.eventId)?body.eventId:null,
        body.label,String(body.note||"").slice(0,1000)).run();
    return json({ok:true});
  }
  const m=path.match(/^\/api\/sessions\/([a-zA-Z0-9_-]{8,100})(\/export)?$/);
  if(method==="GET"&&m){
    return m[2]?csvExport(env.DB,m[1]):latestSession(env.DB,m[1]);
  }
  return failure("Endpoint not found.",404);
}
export default {
  async fetch(request,env) {
    try{return cors(await handle(request,env));}
    catch(e){
      console.error("Motion Lab error",e);
      if(e instanceof SyntaxError)return cors(failure("Invalid JSON.",400));
      if(e.message?.includes("rules")||e.message?.includes("must be between")
          ||e.message?.includes("Payload"))return cors(failure(e.message,400));
      return cors(failure("Unexpected server error.",500));
    }
  }
};
