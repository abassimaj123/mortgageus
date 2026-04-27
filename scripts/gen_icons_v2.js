#!/usr/bin/env node
/**
 * MortgageUS Icon Generator v3
 * - US Navy squircle #0A3161
 * - White house centered at x=512 (same proportions as CA/UK)
 * - Mini US flag bottom-right — TaxUS exact proportions (30% × 19%)
 *   positioned just below/right of house corner for zero overlap
 */
const { createCanvas } = require('canvas');
const fs = require('fs');
const path = require('path');

const PRIMARY   = '#0A3161';
const WHITE     = '#FFFFFF';
const FLAG_RED  = '#B71C1C';
const FLAG_BLUE = '#1565C0';

// ─── 5-point star ────────────────────────────────────────────────────────────
function drawStar(ctx, cx, cy, outer, inner) {
  ctx.beginPath();
  for (let i = 0; i < 10; i++) {
    const r = i % 2 === 0 ? outer : inner;
    const a = (i * Math.PI) / 5 - Math.PI / 2;
    i === 0 ? ctx.moveTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r)
            : ctx.lineTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r);
  }
  ctx.closePath();
  ctx.fill();
}

// ─── US flag — TaxUS identical design ────────────────────────────────────────
// fx,fy = top-left; fw,fh = dimensions (all canvas pixels)
function drawUSFlag(ctx, fx, fy, fw, fh) {
  const stripeH = fh / 7;
  [FLAG_RED, WHITE, FLAG_RED, WHITE, FLAG_RED, WHITE, FLAG_RED].forEach((c, i) => {
    ctx.fillStyle = c;
    ctx.fillRect(fx, fy + i * stripeH, fw, stripeH + 0.5);
  });

  // Canton
  const cw = fw * 0.42;
  const ch = stripeH * 4;
  ctx.fillStyle = FLAG_BLUE;
  ctx.fillRect(fx, fy, cw, ch);

  // 4 stars (2×2)
  ctx.fillStyle = WHITE;
  const sr = stripeH * 0.44;
  [
    [fx + cw * 0.28, fy + ch * 0.25],
    [fx + cw * 0.72, fy + ch * 0.25],
    [fx + cw * 0.28, fy + ch * 0.75],
    [fx + cw * 0.72, fy + ch * 0.75],
  ].forEach(([x, y]) => drawStar(ctx, x, y, sr, sr * 0.42));

  // Border
  ctx.strokeStyle = 'rgba(255,255,255,0.55)';
  ctx.lineWidth = Math.max(0.5, fh * 0.025);
  ctx.strokeRect(fx + 0.5, fy + 0.5, fw - 1, fh - 1);
}

// ─── Draw main icon (1024 coordinate space) ──────────────────────────────────
function drawIcon(canvas) {
  const ctx = canvas.getContext('2d');
  const S = canvas.width;
  const s = S / 1024;

  ctx.clearRect(0, 0, S, S);

  // Navy squircle
  ctx.beginPath();
  ctx.roundRect(0, 0, S, S, 230 * s);
  ctx.fillStyle = PRIMARY;
  ctx.fill();

  // White house — centered at x=512, same coords as CA & UK
  ctx.beginPath();
  ctx.moveTo(232 * s, 540 * s);
  ctx.lineTo(512 * s, 275 * s);
  ctx.lineTo(792 * s, 540 * s);
  ctx.closePath();
  ctx.fillStyle = WHITE;
  ctx.fill();

  ctx.fillStyle = WHITE;
  ctx.fillRect(677 * s, 390 * s, 65 * s, 100 * s); // chimney
  ctx.fillRect(297 * s, 540 * s, 430 * s, 280 * s); // body (right edge x=727, bottom y=820)

  ctx.fillStyle = PRIMARY;
  ctx.fillRect(467 * s, 660 * s, 90 * s, 160 * s); // door (center x=512)

  // US flag — TaxUS proportions: 30% wide × 19% tall
  // Positioned clear of house corner (house: x≤727, y≤820)
  // fx=750 (23px right of house), fy=835 (15px below house bottom)
  const fw = Math.round(0.30 * S);   // 30% — TaxUS exact
  const fh = Math.round(0.19 * S);   // 19% — TaxUS exact
  const fx = S - fw - Math.round(0.04 * S);  // TaxUS exact: s-fw-0.04*s
  const fy = S - fh - Math.round(0.04 * S);  // TaxUS exact: s-fh-0.04*s
  // At S=1024: fx=676, fy=788 → overlaps house. Clamp to clear house corner:
  const fxSafe = Math.max(fx, Math.round(750 * s));
  const fySafe = Math.max(fy, Math.round(835 * s));
  drawUSFlag(ctx, fxSafe, fySafe, fw, fh);
}

// ─── Adaptive foreground (safe zone, transparent bg) ─────────────────────────
function drawForeground(canvas) {
  const ctx = canvas.getContext('2d');
  const S = canvas.width;
  const s = S / 1024;

  ctx.clearRect(0, 0, S, S);

  // House centered at x=512
  ctx.beginPath();
  ctx.moveTo(327 * s, 590 * s);
  ctx.lineTo(512 * s, 400 * s);
  ctx.lineTo(697 * s, 590 * s);
  ctx.closePath();
  ctx.fillStyle = WHITE;
  ctx.fill();

  ctx.fillStyle = WHITE;
  ctx.fillRect(632 * s, 460 * s, 45 * s, 70 * s);
  ctx.fillRect(367 * s, 590 * s, 290 * s, 200 * s); // body right x=657, bottom y=790

  ctx.fillStyle = PRIMARY;
  ctx.fillRect(489 * s, 680 * s, 46 * s, 110 * s);

  // Flag in safe zone — clear of house (house ends at x=657, y=790)
  const fw = Math.round(0.22 * S);
  const fh = Math.round(fw * 0.634);
  const fx = Math.round(670 * s);
  const fy = Math.round(800 * s);
  drawUSFlag(ctx, fx, fy, fw, fh);
}

// ─── Splash logo (512 viewBox, 256px canvas) ─────────────────────────────────
function drawSplashLogo(canvas) {
  const ctx = canvas.getContext('2d');
  const S = canvas.width;
  const s = S / 512;

  ctx.clearRect(0, 0, S, S);

  ctx.beginPath();
  ctx.roundRect(0, 0, S, S, 115 * s);
  ctx.fillStyle = WHITE;
  ctx.fill();

  // Navy house (already centered at x=256 in 512 space)
  ctx.beginPath();
  ctx.moveTo(115 * s, 270 * s);
  ctx.lineTo(256 * s, 135 * s);
  ctx.lineTo(397 * s, 270 * s);
  ctx.closePath();
  ctx.fillStyle = PRIMARY;
  ctx.fill();

  ctx.fillStyle = PRIMARY;
  ctx.fillRect(340 * s, 200 * s, 33 * s, 50 * s);
  ctx.fillRect(150 * s, 270 * s, 212 * s, 140 * s); // body bottom y=410*s

  ctx.fillStyle = WHITE;
  ctx.fillRect(236 * s, 330 * s, 40 * s, 80 * s); // white door

  // Small flag below house (house bottom ≈ y=205 in 256px canvas)
  const fw = Math.round(S * 0.35);
  const fh = Math.round(fw * 0.634);
  drawUSFlag(ctx, (S - fw) / 2, Math.round(420 * s), fw, fh);
}

// ─── Output ──────────────────────────────────────────────────────────────────
const scriptDir = __dirname;
const brandingDir = path.resolve(scriptDir, '../assets/branding');
if (!fs.existsSync(brandingDir)) fs.mkdirSync(brandingDir, { recursive: true });

const MIPMAP_SIZES = {
  mdpi:    { size: 48,  fgSize: 108 },
  hdpi:    { size: 72,  fgSize: 162 },
  xhdpi:   { size: 96,  fgSize: 216 },
  xxhdpi:  { size: 144, fgSize: 324 },
  xxxhdpi: { size: 192, fgSize: 432 },
};

for (const [density, { size, fgSize }] of Object.entries(MIPMAP_SIZES)) {
  const resDir = path.resolve(scriptDir, `../android/app/src/main/res/mipmap-${density}`);
  if (!fs.existsSync(resDir)) continue;
  const ic = createCanvas(size, size); drawIcon(ic);
  const buf = ic.toBuffer('image/png');
  fs.writeFileSync(path.join(resDir, 'ic_launcher.png'), buf);
  fs.writeFileSync(path.join(resDir, 'ic_launcher_round.png'), buf);
  const fg = createCanvas(fgSize, fgSize); drawForeground(fg);
  fs.writeFileSync(path.join(resDir, 'ic_launcher_foreground.png'), fg.toBuffer('image/png'));
  console.log(`✓ ${density}: ${size}px`);
}

const drawableDir = path.resolve(scriptDir, '../android/app/src/main/res/drawable');
if (fs.existsSync(drawableDir)) {
  const fgD = createCanvas(432, 432); drawForeground(fgD);
  fs.writeFileSync(path.join(drawableDir, 'ic_launcher_foreground.png'), fgD.toBuffer('image/png'));
  const bgD = createCanvas(432, 432);
  { const c = bgD.getContext('2d'); c.fillStyle = PRIMARY; c.fillRect(0,0,432,432); }
  fs.writeFileSync(path.join(drawableDir, 'ic_launcher_background.png'), bgD.toBuffer('image/png'));
  const spD = createCanvas(256, 256); drawSplashLogo(spD);
  fs.writeFileSync(path.join(drawableDir, 'ic_splash.png'), spD.toBuffer('image/png'));
  console.log('✓ drawable/');
}

const ic1024 = createCanvas(1024, 1024); drawIcon(ic1024);
fs.writeFileSync(path.join(brandingDir, 'icon_1024.png'), ic1024.toBuffer('image/png'));
const fgA = createCanvas(1024, 1024); drawForeground(fgA);
fs.writeFileSync(path.join(brandingDir, 'icon_foreground.png'), fgA.toBuffer('image/png'));
const sl = createCanvas(256, 256); drawSplashLogo(sl);
fs.writeFileSync(path.join(brandingDir, 'splash_logo.png'), sl.toBuffer('image/png'));
console.log('✓ assets/branding/');

console.log('\nMortgageUS done — house centered x=512, TaxUS-style flag.');
