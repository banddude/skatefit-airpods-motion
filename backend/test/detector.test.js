import test from "node:test";
import assert from "node:assert/strict";
import { reprocessSamples,validateRules } from "../src/detector.js";
const angle=0.45;
const g=tilt=>({x:Math.sin(tilt),y:0,z:-Math.cos(tilt)});
const calibration={flat:g(0),tail:g(angle),nose:g(-angle)};
const sample=(t,tilt=0)=>({
  source:"headphone",sensorLocation:"left",hostUptime:t,
  gravity:g(tilt),rotationRate:{x:0,y:0,z:0},acceleration:{x:0,y:0,z:0}
});
test("replay detects a sustained manual",()=>{
  const samples=Array.from({length:100},(_,i)=>sample(i/40,i>=10&&i<70?0.2:0));
  const {events,error}=reprocessSamples(samples,calibration);
  assert.equal(error,null);
  assert.ok(events.some(e=>e.kind==="Possible manual"));
});
test("replay detects a nose manual",()=>{
  const samples=Array.from({length:100},(_,i)=>sample(i/40,i>=10&&i<70?-0.2:0));
  assert.ok(reprocessSamples(samples,calibration).events.some(e=>e.kind==="Possible nose manual"));
});
test("rule edits change detection without app rebuild",()=>{
  const samples=Array.from({length:100},(_,i)=>sample(i/40,i>=10&&i<70?0.2:0));
  assert.equal(reprocessSamples(samples,calibration,{minimumManualSeconds:2}).events.length,0);
  assert.equal(reprocessSamples(samples,calibration,{minimumManualSeconds:0.2}).events.length,1);
});
test("phone-only data never becomes skateboard tricks",()=>{
  const samples=Array.from({length:100},(_,i)=>({...sample(i/40,0.2),source:"phone"}));
  assert.equal(reprocessSamples(samples,calibration).events.length,0);
});
test("reject unknown rule keys and non-finite values",()=>{
  assert.throws(()=>validateRules({remoteCode:"rm -rf /"}));
  assert.throws(()=>validateRules({manualPitchDegrees:NaN}));
});
test("no calibration fails closed",()=>{
  assert.ok(reprocessSamples([sample(1,0.2)],null).error);
});

test("sideways roll is not classified as manual",()=>{
  const samples=Array.from({length:100},(_,i)=>({
    ...sample(i/40,0),
    gravity:{x:0,y:Math.sin(.3),z:-Math.cos(.3)}
  }));
  assert.equal(reprocessSamples(samples,calibration).events.length,0);
});
