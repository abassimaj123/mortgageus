#!/usr/bin/env node
/**
 * MortgageUS Icon Generator
 * Uses canvas (npm) for crisp text rendering of the $ sign.
 * Design: Navy #1B3A6B bg, white house silhouette, gold $ (font), red US stripe.
 */
'use strict';
const { createCanvas } = require('canvas');
const fs   = require('fs');
const path = require('path');

// ── Brand colors ──────────────────────────────────────────────────────────────
const NAVY  = '#1B3A6B';
const WHITE = '#FFFFFF';
const GOLD  = '#D4A017';
const RED   = '#B22234';

// ── Content scale: 72% with 14% padding each side ────────────────────────────
const PAD = 0.14;
const SC  = 1 - 2 * PAD;           // 0.72
const t   = (f) => PAD + f * SC;   // map coord into padded space

// ── Draw icon onto a canvas ───────────────────────────────────────────────────
function drawIcon(size, transparent = false) {
  const c   = createCanvas(size, size);
  const ctx = c.getContext('2d');
  const s   = size;

  if (!transparent) {
    // Navy background
    ctx.fillStyle = NAVY;
    ctx.fillRect(0, 0, s, s);
    // US red stripe at bottom (8%)
    ctx.fillStyle = RED;
    ctx.fillRect(0, s * 0.895, s, s * 0.105);
    // White separator
    ctx.fillStyle = WHITE;
    ctx.fillRect(0, s * 0.875, s, s * 0.020);
  }

  // ── White house body ───────────────────────────────────────────────────────
  ctx.fillStyle = WHITE;
  ctx.fillRect(
    s * t(0.22), s * t(0.50),
    s * (t(0.78) - t(0.22)), s * (t(0.875) - t(0.50))
  );

  // ── Roof triangle ──────────────────────────────────────────────────────────
  ctx.beginPath();
  ctx.moveTo(s * t(0.50), s * t(0.14));
  ctx.lineTo(s * t(0.07), s * t(0.535));
  ctx.lineTo(s * t(0.93), s * t(0.535));
  ctx.closePath();
  ctx.fill();

  // ── Chimney ────────────────────────────────────────────────────────────────
  ctx.fillRect(
    s * t(0.60), s * t(0.10),
    s * (t(0.70) - t(0.60)), s * (t(0.31) - t(0.10))
  );

  if (!transparent) {
    // ── Navy cutouts: windows + door ────────────────────────────────────────
    ctx.fillStyle = NAVY;
    const wSz = s * 0.10 * SC;
    const wY  = s * t(0.55);
    ctx.fillRect(s * t(0.28), wY, wSz, wSz);   // left window
    ctx.fillRect(s * t(0.62), wY, wSz, wSz);   // right window

    const dw = s * 0.15 * SC;
    const dh = s * 0.225 * SC;
    const dx = s * t(0.50) - dw / 2;
    const dy = s * t(0.875) - dh;
    ctx.fillRect(dx, dy, dw, dh);              // door body
    ctx.beginPath();                            // door arch
    ctx.arc(s * t(0.50), dy, dw / 2, Math.PI, 0, true);
    ctx.fill();

  }

  // ── Gold $ — sized to fit house body, centered with real glyph metrics ─────
  const houseTop    = s * t(0.535);   // top of visible house body (below roof)
  const houseBot    = s * t(0.875);   // bottom of house body
  const houseH      = houseBot - houseTop;
  const dollarSize  = Math.round(houseH * 0.78); // 78% of available height
  ctx.fillStyle     = GOLD;
  ctx.font          = `bold ${dollarSize}px Arial, sans-serif`;
  ctx.textAlign     = 'center';
  ctx.textBaseline  = 'alphabetic';
  const m  = ctx.measureText('$');
  const gH = m.actualBoundingBoxAscent + m.actualBoundingBoxDescent;
  const gY = houseTop + (houseH - gH) / 2 + m.actualBoundingBoxAscent;
  ctx.fillText('$', s * 0.50, gY);

  return c;
}

// ── Resize via canvas ─────────────────────────────────────────────────────────
function resize(src, dw, dh) {
  const c   = createCanvas(dw, dh);
  const ctx = c.getContext('2d');
  ctx.drawImage(src, 0, 0, dw, dh);
  return c;
}

// ── Write helper ──────────────────────────────────────────────────────────────
const ROOT        = path.join(__dirname, '..');
const ANDROID_RES = path.join(ROOT, 'android', 'app', 'src', 'main', 'res');
const IOS_ICONS   = path.join(ROOT, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset');

function writePNG(filePath, canvas) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, canvas.toBuffer('image/png'));
  console.log(`  ✓ ${path.relative(ROOT, filePath)}  (${canvas.width}×${canvas.height})`);
}

// ── 1. Master 1024×1024 ───────────────────────────────────────────────────────
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
  const scaled = resize(master, sz, sz);
  writePNG(path.join(ANDROID_RES, dir, 'ic_launcher.png'),       scaled);
  writePNG(path.join(ANDROID_RES, dir, 'ic_launcher_round.png'), scaled);
}

// ── 3. Android adaptive icon ──────────────────────────────────────────────────
console.log('\n[3] Android adaptive icon layers:');
const FG_SIZE = 432;
const fg = drawIcon(FG_SIZE, true);
writePNG(path.join(ANDROID_RES, 'drawable', 'ic_launcher_foreground.png'), fg);

// Solid navy background tile
const bgCanvas = createCanvas(108, 108);
const bgCtx    = bgCanvas.getContext('2d');
bgCtx.fillStyle = NAVY;
bgCtx.fillRect(0, 0, 108, 108);
writePNG(path.join(ANDROID_RES, 'drawable', 'ic_launcher_background.png'), bgCanvas);

// ── 4. iOS AppIcon ────────────────────────────────────────────────────────────
console.log('\n[4] iOS AppIcon sizes:');
const iosSizes = [
  { name: 'Icon-App-20x20@2x.png',     size: 40   },
  { name: 'Icon-App-20x20@3x.png',     size: 60   },
  { name: 'Icon-App-29x29@1x.png',     size: 29   },
  { name: 'Icon-App-29x29@2x.png',     size: 58   },
  { name: 'Icon-App-29x29@3x.png',     size: 87   },
  { name: 'Icon-App-40x40@2x.png',     size: 80   },
  { name: 'Icon-App-40x40@3x.png',     size: 120  },
  { name: 'Icon-App-60x60@2x.png',     size: 120  },
  { name: 'Icon-App-60x60@3x.png',     size: 180  },
  { name: 'Icon-App-76x76@1x.png',     size: 76   },
  { name: 'Icon-App-76x76@2x.png',     size: 152  },
  { name: 'Icon-App-83.5x83.5@2x.png', size: 167  },
  { name: 'Icon-App-1024x1024@1x.png', size: 1024 },
];
for (const { name, size } of iosSizes) {
  const scaled = size === MSIZE ? master : resize(master, size, size);
  writePNG(path.join(IOS_ICONS, name), scaled);
}

// ── 5. Feature graphic 1024×500 ───────────────────────────────────────────────
console.log('\n[5] Play Store feature graphic 1024×500:');
const FW = 1024, FH = 500;
const feat    = createCanvas(FW, FH);
const featCtx = feat.getContext('2d');
featCtx.fillStyle = NAVY;
featCtx.fillRect(0, 0, FW, FH);
featCtx.fillStyle = RED;
featCtx.fillRect(FW * 0.68, 0, FW * 0.32, FH);
// Diagonal separator
featCtx.strokeStyle = WHITE;
featCtx.lineWidth   = 10;
featCtx.beginPath();
featCtx.moveTo(FW * 0.68, 0);
featCtx.lineTo(FW * 0.68 + FH * 0.14, FH);
featCtx.stroke();
// Mini icon
const MINI     = 260;
const miniIcon = resize(master, MINI, MINI);
featCtx.drawImage(miniIcon, Math.round(FW * 0.17), Math.round((FH - MINI) / 2));
// Gold accent bars
featCtx.fillStyle = GOLD;
featCtx.fillRect(FW * 0.75, FH * 0.30, FW * 0.21, FH * 0.12);
featCtx.globalAlpha = 0.47;
featCtx.fillStyle = WHITE;
featCtx.fillRect(FW * 0.75, FH * 0.48, FW * 0.19, FH * 0.08);
featCtx.globalAlpha = 0.31;
featCtx.fillRect(FW * 0.75, FH * 0.62, FW * 0.15, FH * 0.06);
featCtx.globalAlpha = 1;
writePNG(path.join(ROOT, 'docs', 'store-assets', 'feature_graphic_1024x500.png'), feat);

// ── 6. Splash screen 1080×1920 ────────────────────────────────────────────────
console.log('\n[6] Splash screen 1080×1920:');
const SW = 1080, SH = 1920;
const splash    = createCanvas(SW, SH);
const splashCtx = splash.getContext('2d');
splashCtx.fillStyle = NAVY;
splashCtx.fillRect(0, 0, SW, SH);
const SPLASH_ICON = 240;
const splIcon     = resize(master, SPLASH_ICON, SPLASH_ICON);
splashCtx.drawImage(splIcon,
  Math.round((SW - SPLASH_ICON) / 2),
  Math.round((SH - SPLASH_ICON) / 2));
writePNG(path.join(ROOT, 'assets', 'images', 'splash.png'), splash);

// ── 7. Flutter splash asset icon 192×192 ─────────────────────────────────────
console.log('\n[7] Flutter splash asset icon:');
const splashAsset = resize(master, 192, 192);
writePNG(path.join(ROOT, 'assets', 'images', 'app_icon.png'), splashAsset);

console.log('\n✅ All icons generated!\n');
