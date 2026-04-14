#!/usr/bin/env node
/**
 * MortgageUS Icon Generator
 * Generates all PNG icons using Node.js built-in modules only (no npm deps).
 * Design: Navy #1B3A6B bg, white house silhouette, gold #D4A017 $ sign, red US stripe.
 */
'use strict';
const zlib = require('zlib');
const fs   = require('fs');
const path = require('path');

// ── CRC32 ─────────────────────────────────────────────────────────────────────
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

// ── PNG encoder ───────────────────────────────────────────────────────────────
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
  ihdr[8]=8; ihdr[9]=6; // 8-bit RGBA
  const rows = [];
  for (let y = 0; y < h; y++) {
    const row = Buffer.alloc(1 + w * 4);
    row[0] = 0; // filter: None
    rgba.copy(row, 1, y * w * 4, (y + 1) * w * 4);
    rows.push(row);
  }
  const idat = zlib.deflateSync(Buffer.concat(rows), { level: 6 });
  return Buffer.concat([sig,
    pngChunk('IHDR', ihdr),
    pngChunk('IDAT', idat),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

// ── Canvas helpers ────────────────────────────────────────────────────────────
function newCanvas(w, h, r=0, g=0, b=0, a=255) {
  const buf = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    buf[i*4]=r; buf[i*4+1]=g; buf[i*4+2]=b; buf[i*4+3]=a;
  }
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
  const mnx=Math.floor(Math.min(ax,bx,cx));
  const mxx=Math.ceil (Math.max(ax,bx,cx));
  const mny=Math.floor(Math.min(ay,by,cy));
  const mxy=Math.ceil (Math.max(ay,by,cy));
  const sgn=(x1,y1,x2,y2,x3,y3)=>(x1-x3)*(y2-y3)-(x2-x3)*(y1-y3);
  for (let py=mny; py<=mxy; py++)
    for (let px=mnx; px<=mxx; px++) {
      const d1=sgn(px,py,ax,ay,bx,by);
      const d2=sgn(px,py,bx,by,cx,cy);
      const d3=sgn(px,py,cx,cy,ax,ay);
      if (!((d1<0||d2<0||d3<0)&&(d1>0||d2>0||d3>0)))
        put(buf,w,h,px,py,r,g,b,a);
    }
}
function fillArc(buf, w, h, cx,cy, r1,r2, a0,a1, r,g,b,a=255) {
  // filled annulus segment from angle a0 to a1 (radians)
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

// Composite src onto dst at offset (ox, oy)
function blit(dst, dw, dh, src, sw, sh, ox, oy) {
  for (let y=0; y<sh; y++) for (let x=0; x<sw; x++) {
    const si=(y*sw+x)*4;
    if (src[si+3]<10) continue;
    const tx=ox+x, ty=oy+y;
    if (tx<0||tx>=dw||ty<0||ty>=dh) continue;
    put(dst,dw,dh,tx,ty,src[si],src[si+1],src[si+2],src[si+3]);
  }
}

// Nearest-neighbor resize
function resize(src, sw, sh, dw, dh) {
  const dst=Buffer.alloc(dw*dh*4);
  for (let y=0; y<dh; y++) for (let x=0; x<dw; x++) {
    const sy=Math.min(sh-1,Math.floor(y*sh/dh));
    const sx=Math.min(sw-1,Math.floor(x*sw/dw));
    const si=(sy*sw+sx)*4, di=(y*dw+x)*4;
    dst[di]=src[si]; dst[di+1]=src[si+1]; dst[di+2]=src[si+2]; dst[di+3]=src[si+3];
  }
  return dst;
}

// ── Brand colors ──────────────────────────────────────────────────────────────
const NAVY  = [27,  58, 107]; // #1B3A6B
const WHITE = [255,255, 255];
const GOLD  = [212,160,  23]; // #D4A017
const RED   = [178, 34,  52]; // US flag red

// ── Dollar sign ───────────────────────────────────────────────────────────────
function drawDollar(buf, s, cx, cy, radius) {
  const [r,g,b] = GOLD;
  const sw = Math.max(2, radius * 0.24);

  // Vertical bar (extends above and below S)
  fillRect(buf,s,s, cx-sw*0.85,cy-radius*1.65, cx+sw*0.85,cy+radius*1.65, r,g,b);

  // Upper C — opens right (arc ~100° to 440°, i.e. 100°..260° visually)
  const ucx = cx + radius*0.06, ucy = cy - radius*0.72;
  fillArc(buf,s,s, ucx,ucy, radius*0.48-sw, radius*0.48+sw,
    Math.PI*0.55, Math.PI*1.95, r,g,b);

  // Lower C — opens left (arc ~280° to 620°)
  const lcx = cx - radius*0.06, lcy = cy + radius*0.72;
  fillArc(buf,s,s, lcx,lcy, radius*0.48-sw, radius*0.48+sw,
    Math.PI*1.55, Math.PI*2.95, r,g,b);
}

// ── House icon renderer ───────────────────────────────────────────────────────
// Content scaled to 72% with 14% padding each side.
// House spans ~62% of icon; dollar sign scales proportionally.
function drawIcon(size, transparent=false) {
  const s = size;
  const buf = transparent
    ? newCanvas(s,s, 0,0,0, 0)
    : newCanvas(s,s, ...NAVY);

  const PAD = 0.14;            // 14% padding each side
  const SC  = 1 - 2 * PAD;    // 0.72 content scale
  const t   = (f) => PAD + f * SC; // map [0,1] coord into padded space

  if (!transparent) {
    // US accent stripe at bottom (8%)
    fillRect(buf,s,s, 0,s*0.895, s,s,       ...RED);
    // White separator line
    fillRect(buf,s,s, 0,s*0.875, s,s*0.895, ...WHITE);
  }

  // House body
  fillRect(buf,s,s, s*t(0.22),s*t(0.50), s*t(0.78),s*t(0.875), ...WHITE);

  // Roof triangle
  fillTri(buf,s,s,
    s*t(0.50), s*t(0.14),   // apex
    s*t(0.07), s*t(0.535),  // bottom-left
    s*t(0.93), s*t(0.535),  // bottom-right
    ...WHITE);

  // Chimney
  fillRect(buf,s,s, s*t(0.60),s*t(0.10), s*t(0.70),s*t(0.31), ...WHITE);

  if (!transparent) {
    const wSz=s*0.10*SC, wY=s*t(0.55);
    // Left window
    fillRect(buf,s,s, s*t(0.28),wY, s*t(0.28)+wSz,wY+wSz, ...NAVY);
    // Right window
    fillRect(buf,s,s, s*t(0.62),wY, s*t(0.62)+wSz,wY+wSz, ...NAVY);
    // Door arch
    const dw=s*0.15*SC, dh=s*0.225*SC;
    const dx=s*t(0.50)-dw/2, dy=s*t(0.875)-dh;
    fillRect(buf,s,s, dx,dy, dx+dw,s*t(0.875), ...NAVY);
    fillCircle(buf,s,s, s*t(0.50),dy, dw/2, ...NAVY);
  }

  // Dollar sign overlay
  drawDollar(buf, s, s*t(0.50), s*t(0.625), s*0.135*SC);

  return buf;
}

// ── Write helpers ─────────────────────────────────────────────────────────────
function writePNG(filePath, buf, w, h) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, encodePNG(buf, w, h));
  console.log(`  ✓ ${path.relative(ROOT, filePath)}  (${w}×${h})`);
}

const ROOT = path.join(__dirname, '..');
const ANDROID_RES = path.join(ROOT,'android','app','src','main','res');
const IOS_ICONS   = path.join(ROOT,'ios','Runner','Assets.xcassets','AppIcon.appiconset');

// ── 1. Generate master 1024×1024 ─────────────────────────────────────────────
console.log('\n[1] Generating master icon 1024×1024...');
const MSIZE  = 1024;
const master = drawIcon(MSIZE, false);

// ── 2. Android mipmap ─────────────────────────────────────────────────────────
console.log('\n[2] Android mipmap icons:');
const mipmapSizes = {
  'mipmap-mdpi':    48,
  'mipmap-hdpi':    72,
  'mipmap-xhdpi':   96,
  'mipmap-xxhdpi':  144,
  'mipmap-xxxhdpi': 192,
};
for (const [dir, sz] of Object.entries(mipmapSizes)) {
  const scaled = resize(master, MSIZE, MSIZE, sz, sz);
  writePNG(path.join(ANDROID_RES,dir,'ic_launcher.png'),       scaled, sz, sz);
  writePNG(path.join(ANDROID_RES,dir,'ic_launcher_round.png'), scaled, sz, sz);
}

// ── 3. Android adaptive icon ───────────────────────────────────────────────────
console.log('\n[3] Android adaptive icon layers:');
// Foreground: 432×432 (xxxhdpi 108dp) — house+$ on transparent
const FG_SIZE = 432;
const fg = drawIcon(FG_SIZE, true);
writePNG(path.join(ANDROID_RES,'drawable','ic_launcher_foreground.png'), fg, FG_SIZE, FG_SIZE);
// Background: solid navy
const bgCanvas = newCanvas(108, 108, ...NAVY);
writePNG(path.join(ANDROID_RES,'drawable','ic_launcher_background.png'), bgCanvas, 108, 108);

// ── 4. iOS AppIcon ────────────────────────────────────────────────────────────
console.log('\n[4] iOS AppIcon sizes:');
const iosSizes = [
  { name:'Icon-App-20x20@2x.png',    size:40  },
  { name:'Icon-App-20x20@3x.png',    size:60  },
  { name:'Icon-App-29x29@1x.png',    size:29  },
  { name:'Icon-App-29x29@2x.png',    size:58  },
  { name:'Icon-App-29x29@3x.png',    size:87  },
  { name:'Icon-App-40x40@2x.png',    size:80  },
  { name:'Icon-App-40x40@3x.png',    size:120 },
  { name:'Icon-App-60x60@2x.png',    size:120 },
  { name:'Icon-App-60x60@3x.png',    size:180 },
  { name:'Icon-App-76x76@1x.png',    size:76  },
  { name:'Icon-App-76x76@2x.png',    size:152 },
  { name:'Icon-App-83.5x83.5@2x.png',size:167 },
  { name:'Icon-App-1024x1024@1x.png',size:1024},
];
for (const {name, size} of iosSizes) {
  const scaled = size === MSIZE ? master : resize(master, MSIZE, MSIZE, size, size);
  writePNG(path.join(IOS_ICONS, name), scaled, size, size);
}

// ── 5. Feature graphic 1024×500 ──────────────────────────────────────────────
console.log('\n[5] Play Store feature graphic 1024×500:');
const FW=1024, FH=500;
const feat = newCanvas(FW,FH,...NAVY);
// Right panel: red
fillRect(feat,FW,FH, FW*0.68,0, FW,FH, ...RED);
// Diagonal separator (white)
for (let fy=0; fy<FH; fy++) {
  const sepX = Math.round(FW*0.68 + fy*0.14);
  for (let dx=-5; dx<=5; dx++) put(feat,FW,FH,sepX+dx,fy,...WHITE);
}
// Mini icon (260px) on left half
const MINI=260;
const mini = resize(master, MSIZE, MSIZE, MINI, MINI);
blit(feat,FW,FH,mini,MINI,MINI, Math.round(FW*0.17), Math.round((FH-MINI)/2));
// Gold accent bar (simulates text area)
fillRect(feat,FW,FH, FW*0.75,FH*0.30, FW*0.96,FH*0.42, ...GOLD);
fillRect(feat,FW,FH, FW*0.75,FH*0.48, FW*0.94,FH*0.56, ...WHITE,120);
fillRect(feat,FW,FH, FW*0.75,FH*0.62, FW*0.90,FH*0.68, ...WHITE,80);
writePNG(path.join(ROOT,'docs','store-assets','feature_graphic_1024x500.png'), feat, FW, FH);

// ── 6. Splash screen 1080×1920 ────────────────────────────────────────────────
console.log('\n[6] Splash screen 1080×1920:');
const SW=1080, SH=1920;
const splash = newCanvas(SW,SH,...NAVY);
const SPLASH_ICON=240;
const splIcon = resize(master, MSIZE, MSIZE, SPLASH_ICON, SPLASH_ICON);
blit(splash,SW,SH,splIcon,SPLASH_ICON,SPLASH_ICON,
  Math.round((SW-SPLASH_ICON)/2),
  Math.round((SH-SPLASH_ICON)/2));
writePNG(path.join(ROOT,'assets','images','splash.png'), splash, SW, SH);

// ── 7. Flutter splash icon 192×192 (assets/images/) ─────────────────────────
console.log('\n[7] Flutter splash asset icon:');
const splashAsset = resize(master, MSIZE, MSIZE, 192, 192);
writePNG(path.join(ROOT, 'assets', 'images', 'app_icon.png'), splashAsset, 192, 192);

console.log('\n✅ All icons generated!\n');
