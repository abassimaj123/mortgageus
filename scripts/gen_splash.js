// Quick script to generate ic_splash.png (solid bg, 192x192)
// Reuses logic from generate_icons.js
'use strict';
const zlib = require('zlib');
const fs   = require('fs');
const path = require('path');

const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xFFFFFFFF;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}
function pngChunk(type, data) {
  const t = Buffer.from(type, 'ascii');
  const l = Buffer.alloc(4); l.writeUInt32BE(data.length);
  const c = Buffer.alloc(4); c.writeUInt32BE(crc32(Buffer.concat([t, data])));
  return Buffer.concat([l, t, data, c]);
}
function encodePNG(rgba, w, h) {
  const sig  = Buffer.from([137,80,78,71,13,10,26,10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8]=8; ihdr[9]=6;
  const rows = [];
  for (let y = 0; y < h; y++) {
    const row = Buffer.alloc(1 + w * 4);
    row[0] = 0;
    rgba.copy(row, 1, y * w * 4, (y + 1) * w * 4);
    rows.push(row);
  }
  const idat = zlib.deflateSync(Buffer.concat(rows), { level: 6 });
  return Buffer.concat([sig, pngChunk('IHDR',ihdr), pngChunk('IDAT',idat), pngChunk('IEND',Buffer.alloc(0))]);
}
function newCanvas(w, h, r=0, g=0, b=0, a=255) {
  const buf = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) { buf[i*4]=r; buf[i*4+1]=g; buf[i*4+2]=b; buf[i*4+3]=a; }
  return buf;
}
function put(buf, w, h, x, y, r, g, b, a=255) {
  x=Math.round(x); y=Math.round(y);
  if (x<0||x>=w||y<0||y>=h) return;
  const i=(y*w+x)*4;
  const fa=a/255, ba=buf[i+3]/255, oa=fa+ba*(1-fa);
  if (oa<1e-4){buf[i+3]=0;return;}
  buf[i  ]=Math.round((r*fa+buf[i  ]*ba*(1-fa))/oa);
  buf[i+1]=Math.round((g*fa+buf[i+1]*ba*(1-fa))/oa);
  buf[i+2]=Math.round((b*fa+buf[i+2]*ba*(1-fa))/oa);
  buf[i+3]=Math.round(oa*255);
}
function fillRect(buf, w, h, x1,y1,x2,y2, r,g,b,a=255) {
  for (let y=Math.max(0,y1|0); y<Math.min(h,Math.ceil(y2)); y++)
    for (let x=Math.max(0,x1|0); x<Math.min(w,Math.ceil(x2)); x++)
      put(buf,w,h,x,y,r,g,b,a);
}
function fillCircle(buf, w, h, cx,cy,rad, r,g,b,a=255) {
  const r2=rad*rad;
  for (let y=(cy-rad)|0; y<=Math.ceil(cy+rad); y++)
    for (let x=(cx-rad)|0; x<=Math.ceil(cx+rad); x++) {
      const dx=x-cx,dy=y-cy;
      if (dx*dx+dy*dy<=r2) put(buf,w,h,x,y,r,g,b,a);
    }
}
function fillTri(buf, w, h, ax,ay,bx,by,cx,cy, r,g,b,a=255) {
  const mnx=Math.floor(Math.min(ax,bx,cx)), mxx=Math.ceil(Math.max(ax,bx,cx));
  const mny=Math.floor(Math.min(ay,by,cy)), mxy=Math.ceil(Math.max(ay,by,cy));
  const sgn=(x1,y1,x2,y2,x3,y3)=>(x1-x3)*(y2-y3)-(x2-x3)*(y1-y3);
  for (let py=mny; py<=mxy; py++)
    for (let px=mnx; px<=mxx; px++) {
      const d1=sgn(px,py,ax,ay,bx,by), d2=sgn(px,py,bx,by,cx,cy), d3=sgn(px,py,cx,cy,ax,ay);
      if (!((d1<0||d2<0||d3<0)&&(d1>0||d2>0||d3>0))) put(buf,w,h,px,py,r,g,b,a);
    }
}
function fillArc(buf, w, h, cx,cy, r1,r2, a0,a1, r,g,b,a=255) {
  const r2sq=r2*r2, r1sq=r1*r1;
  for (let py=(cy-r2)|0; py<=Math.ceil(cy+r2); py++)
    for (let px=(cx-r2)|0; px<=Math.ceil(cx+r2); px++) {
      const dx=px-cx, dy=py-cy, dsq=dx*dx+dy*dy;
      if (dsq<r1sq||dsq>r2sq) continue;
      let ang=Math.atan2(dy,dx);
      while (ang<a0) ang+=2*Math.PI;
      if (ang<=a1) put(buf,w,h,px,py,r,g,b,a);
    }
}

const NAVY=[27,58,107], WHITE=[255,255,255], GOLD=[212,160,23], RED=[178,34,52];

function drawDollar(buf, s, cx, cy, _unused) {
  const coinR = s * 0.155;
  const [gr,gg,gb] = GOLD;
  const [wr,wg,wb] = WHITE;
  fillCircle(buf, s, s, cx, cy, coinR, gr, gg, gb);
  const sw = Math.max(1.5, coinR * 0.17);
  const aR = coinR * 0.46;
  fillRect(buf, s, s, cx - sw, cy - coinR * 1.20, cx + sw, cy + coinR * 1.20, wr, wg, wb);
  fillArc(buf, s, s, cx, cy - aR * 0.54, aR - sw * 0.5, aR + sw * 0.5,
    Math.PI * 0.5, Math.PI * 1.5, wr, wg, wb);
  fillArc(buf, s, s, cx, cy + aR * 0.54, aR - sw * 0.5, aR + sw * 0.5,
    Math.PI * 1.5, Math.PI * 2.5, wr, wg, wb);
}

function drawIcon(size) {
  const s   = size;
  const buf = newCanvas(s,s, ...NAVY);
  const PAD = 0.14;
  const SC  = 1 - 2 * PAD;    // 0.72
  const t   = (f) => PAD + f * SC;
  fillRect(buf,s,s, 0,s*0.895, s,s, ...RED);
  fillRect(buf,s,s, 0,s*0.875, s,s*0.895, ...WHITE);
  fillRect(buf,s,s, s*t(0.22),s*t(0.50), s*t(0.78),s*t(0.875), ...WHITE);
  fillTri(buf,s,s, s*t(0.50),s*t(0.14), s*t(0.07),s*t(0.535), s*t(0.93),s*t(0.535), ...WHITE);
  fillRect(buf,s,s, s*t(0.60),s*t(0.10), s*t(0.70),s*t(0.31), ...WHITE);
  const wSz=s*0.10*SC, wY=s*t(0.55);
  fillRect(buf,s,s, s*t(0.28),wY, s*t(0.28)+wSz,wY+wSz, ...NAVY);
  fillRect(buf,s,s, s*t(0.62),wY, s*t(0.62)+wSz,wY+wSz, ...NAVY);
  const dw=s*0.15*SC, dh=s*0.225*SC;
  const dx=s*t(0.50)-dw/2, dy=s*t(0.875)-dh;
  fillRect(buf,s,s, dx,dy, dx+dw,s*t(0.875), ...NAVY);
  fillCircle(buf,s,s, s*t(0.50),dy, dw/2, ...NAVY);
  drawDollar(buf, s, s*t(0.50), s*t(0.625), 0);
  return buf;
}

const ROOT = path.join(__dirname, '..');
const dst = path.join(ROOT, 'android','app','src','main','res','drawable','ic_splash.png');
const icon = drawIcon(192);
fs.writeFileSync(dst, encodePNG(icon, 192, 192));
console.log('✓ ic_splash.png (192×192) written');
