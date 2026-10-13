export const DEFAULT_RULES = Object.freeze({
  manualPitchDegrees: 6,
  minimumManualSeconds: 0.45,
  impactThresholdG: 1.9,
  rotationStartRate: 2.6,
  movementThresholdG: 0.9,
  maxCandidateSeconds: 1.25
});
export const RANGES = Object.freeze({
  manualPitchDegrees: [1, 30],
  minimumManualSeconds: [0.1, 10],
  impactThresholdG: [0.1, 12],
  rotationStartRate: [0.5, 30],
  movementThresholdG: [0.1, 6],
  maxCandidateSeconds: [0.2, 8]
});
export function validateRules(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("rules must be an object");
  if (Object.keys(value).some(key => !(key in RANGES))) throw new Error("unknown rule parameter");
  const rules = { ...DEFAULT_RULES };
  for (const [key, [min, max]] of Object.entries(RANGES)) {
    if (key in value) {
      const number = value[key];
      if (typeof number !== "number" || !Number.isFinite(number) || number < min || number > max) {
        throw new Error(key + " must be between " + min + " and " + max);
      }
      rules[key] = number;
    }
  }
  return rules;
}
function dot(a,b) { return a.x*b.x+a.y*b.y+a.z*b.z; }
function subtract(a,b) { return {x:a.x-b.x,y:a.y-b.y,z:a.z-b.z}; }
function scale(a,f) { return {x:a.x*f,y:a.y*f,z:a.z*f}; }
function cross(a,b) { return {x:a.y*b.z-a.z*b.y,y:a.z*b.x-a.x*b.z,z:a.x*b.y-a.y*b.x}; }
function norm(a) { return Math.sqrt(dot(a,a)); }
function unit(a) { const n=norm(a);return n>1e-8?scale(a,1/n):null; }
function radiansBetween(a,b) { return Math.atan2(norm(cross(a,b)), dot(a,b)); }
function makeAxes(calibration) {
  if(!calibration||!calibration.flat||!calibration.tail||!calibration.nose)return null;
  const flat=unit(calibration.flat),tail=unit(calibration.tail),nose=unit(calibration.nose);
  if(!flat||!tail||!nose)return null;
  const length=unit(subtract(tail,scale(flat,dot(tail,flat))));
  if(!length)return null;
  if(dot(subtract(tail,flat),length)<=0||dot(subtract(nose,flat),length)>=0)return null;
  const contact=Math.min(radiansBetween(flat,tail),radiansBetween(flat,nose))*180/Math.PI;
  if(contact<5)return null;
  return {flat,length,width:unit(cross(flat,length)),maxManual:Math.max(8,contact-3)};
}
function pitch(sample,axes) {
  const gravity=unit(sample.gravity);if(!gravity)return null;
  // Ignore lateral roll so a primo/railstand tilt isn't called a manual.
  return Math.atan2(dot(gravity,axes.length),dot(gravity,axes.flat))*180/Math.PI;
}
function event(kind,start,end,confidence,detail) { return {kind,start,end,confidence,detail}; }

/** Replay board readings under current remotely editable rule settings. */
export function reprocessSamples(samples,calibration,settings=DEFAULT_RULES,side="left") {
  const rules=validateRules(settings);
  const axes=makeAxes(calibration);
  if(!axes)return {events:[],error:"Calibrate tail, nose, and four wheels before replay."};
  const ordered=samples.filter(s=>s&&(s.source==="headphone"||s.source==="simulation")&&
    (s.sensorLocation===side||s.source==="simulation")&&Number.isFinite(s.hostUptime))
    .sort((a,b)=>a.hostUptime-b.hostUptime);
  const result=[];
  let holdStart=null,holdDirection=0,flight=null,previous=null,roll=0,yaw=0,pitchRotation=0,peak=0;
  for(const s of ordered){
    const t=s.hostUptime, p=pitch(s,axes);
    if(p===null)continue;
    const accel=norm(s.acceleration),rate=norm(s.rotationRate);
    const dir=p>rules.manualPitchDegrees?1:p < -rules.manualPitchDegrees?-1:0;
    const isHold=dir!==0&&Math.abs(p)<axes.maxManual&&rate<2;
    if(isHold){
      if(holdDirection!==dir){holdStart=t;holdDirection=dir;}
    } else {
      if(holdStart!==null&&t-holdStart>=rules.minimumManualSeconds)
        result.push(event(holdDirection>0?"Possible manual":"Possible nose manual",holdStart,t,0.55,
          "Calibrated pitch held for "+(t-holdStart).toFixed(2)+"s. Ground contact not confirmed."));
      holdStart=null;holdDirection=0;
    }
    if(flight===null&&(rate>rules.rotationStartRate||accel>rules.movementThresholdG)){
      flight=t;previous=t;roll=0;yaw=0;pitchRotation=0;peak=accel;
    }
    if(flight!==null){
      const dt=Math.min(0.08,Math.max(0,t-(previous??t)));
      roll+=dot(s.rotationRate,axes.length)*dt;
      yaw+=dot(s.rotationRate,axes.flat)*dt;
      pitchRotation+=dot(s.rotationRate,axes.width)*dt;
      previous=t;peak=Math.max(peak,accel);
      const elapsed=t-flight,landing=accel>rules.impactThresholdG&&elapsed>0.12;
      if(landing||elapsed>rules.maxCandidateSeconds){
        if(elapsed>0.12){
          const flip=Math.abs(roll),shove=Math.abs(yaw);
          const kind=flip>4.3&&shove>3?"Possible flip + shove combination":
            flip>4.3?"Possible flip trick":shove>2.3?"Possible shove-it":
            landing?"Possible ollie / pop":"Unclassified board movement";
          result.push(event(kind,flight,t,kind.includes("Possible")?0.35:0.2,
            "Integrated flip "+(flip*180/Math.PI).toFixed(0)+"°, yaw "+
            (shove*180/Math.PI).toFixed(0)+"°, pitch "+
            (Math.abs(pitchRotation)*180/Math.PI).toFixed(0)+"°; peak "+
            peak.toFixed(1)+"g. Landing not verified."));
        }
        flight=null;previous=null;
      }
    }
  }
  return {events:result,error:null};
}
