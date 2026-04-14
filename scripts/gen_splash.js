// Quick script to generate ic_splash.png (192×192) — uses canvas for crisp $ text
'use strict';
const { createCanvas } = require('canvas');
const fs   = require('fs');
const path = require('path');

const NAVY = '#1B3A6B';
const WHITE = '#FFFFFF';
const GOLD  = '#D4A017';
const RED   = '#B22234';

const PAD = 0.14;
const SC  = 1 - 2 * PAD;
const t   = (f) => PAD + f * SC;

function drawIcon(size) {
  const c   = createCanvas(size, size);
  const ctx = c.getContext('2d');
  const s   = size;

  ctx.fillStyle = NAVY;
  ctx.fillRect(0, 0, s, s);
  ctx.fillStyle = RED;
  ctx.fillRect(0, s * 0.895, s, s * 0.105);
  ctx.fillStyle = WHITE;
  ctx.fillRect(0, s * 0.875, s, s * 0.020);

  // House body
  ctx.fillStyle = WHITE;
  ctx.fillRect(s*t(0.22), s*t(0.50), s*(t(0.78)-t(0.22)), s*(t(0.875)-t(0.50)));
  // Roof
  ctx.beginPath();
  ctx.moveTo(s*t(0.50), s*t(0.14));
  ctx.lineTo(s*t(0.07), s*t(0.535));
  ctx.lineTo(s*t(0.93), s*t(0.535));
  ctx.closePath();
  ctx.fill();
  // Chimney
  ctx.fillRect(s*t(0.60), s*t(0.10), s*(t(0.70)-t(0.60)), s*(t(0.31)-t(0.10)));
  // Windows
  ctx.fillStyle = NAVY;
  const wSz = s*0.10*SC, wY = s*t(0.55);
  ctx.fillRect(s*t(0.28), wY, wSz, wSz);
  ctx.fillRect(s*t(0.62), wY, wSz, wSz);
  // Door
  const dw = s*0.15*SC, dh = s*0.225*SC;
  const dx = s*t(0.50)-dw/2, dy = s*t(0.875)-dh;
  ctx.fillRect(dx, dy, dw, dh);
  ctx.beginPath();
  ctx.arc(s*t(0.50), dy, dw/2, Math.PI, 0, true);
  ctx.fill();

  // Gold $ — sized to visible house body, centered via real glyph metrics
  const houseTop   = s * t(0.535);
  const houseBot   = s * t(0.875);
  const houseH     = houseBot - houseTop;
  const dollarSize = Math.round(houseH * 0.78);
  ctx.fillStyle    = GOLD;
  ctx.font         = `bold ${dollarSize}px Arial, sans-serif`;
  ctx.textAlign    = 'center';
  ctx.textBaseline = 'alphabetic';
  const m  = ctx.measureText('$');
  const gH = m.actualBoundingBoxAscent + m.actualBoundingBoxDescent;
  const gY = houseTop + (houseH - gH) / 2 + m.actualBoundingBoxAscent;
  ctx.fillText('$', s * 0.50, gY);

  return c;
}

const ROOT = path.join(__dirname, '..');
const dst  = path.join(ROOT, 'android', 'app', 'src', 'main', 'res', 'drawable', 'ic_splash.png');
const icon = drawIcon(192);
fs.writeFileSync(dst, icon.toBuffer('image/png'));
console.log('✓ ic_splash.png (192×192) written');
