import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Resvg } from "@resvg/resvg-js";
import QRCode from "qrcode";

const url = "https://tr3k.app/get";
const qr = QRCode.create(url, { errorCorrectionLevel: "M" });
const count = qr.modules.size;
const cell = 14;
const quiet = 4;
const qrSize = (count + quiet * 2) * cell;
let dots = "";
for (let y = 0; y < count; y += 1) {
  for (let x = 0; x < count; x += 1) {
    if (!qr.modules.get(x, y)) continue;
    dots += `<rect x="${(x + quiet) * cell}" y="${(y + quiet) * cell}" width="${cell}" height="${cell}"/>`;
  }
}

const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="1800" viewBox="0 0 1200 1800">
  <rect width="1200" height="1800" fill="#14110e"/>
  <rect x="48" y="48" width="1104" height="1704" rx="36" fill="none" stroke="#e2a53a" stroke-width="4"/>
  <text x="600" y="220" text-anchor="middle" fill="#e2a53a" font-family="Palatino, Georgia, serif" font-size="140">Tr3k</text>
  <text x="600" y="300" text-anchor="middle" fill="#f4ecdf" font-family="Avenir Next, Segoe UI, sans-serif" font-size="36">Saturday, October 24, 2026</text>
  <text x="600" y="352" text-anchor="middle" fill="#f4ecdf" font-family="Avenir Next, Segoe UI, sans-serif" font-size="32">Buford, Georgia</text>
  <rect x="${(1200 - qrSize - 48) / 2}" y="430" width="${qrSize + 48}" height="${qrSize + 48}" rx="24" fill="#f4ecdf"/>
  <g transform="translate(${(1200 - qrSize) / 2} 454)" fill="#14110e">${dots}</g>
  <text x="600" y="${520 + qrSize}" text-anchor="middle" fill="#f4ecdf" font-family="Avenir Next, Segoe UI, sans-serif" font-size="40">Scan to play</text>
  <text x="600" y="${575 + qrSize}" text-anchor="middle" fill="#e2a53a" font-family="Avenir Next, Segoe UI, sans-serif" font-size="48">tr3k.app/get</text>
  <text x="600" y="1500" text-anchor="middle" fill="#f4ecdf" font-family="Avenir Next, Segoe UI, sans-serif" font-size="28">iPhone opens the beta. Everyone else plays on the web.</text>
  <text x="600" y="1560" text-anchor="middle" fill="#c4bfb4" font-family="Avenir Next, Segoe UI, sans-serif" font-size="24">Independent app. Collectibles have no cash value.</text>
</svg>`;

const png = new Resvg(svg, { fitTo: { mode: "width", value: 1200 } }).render().asPng();
const out = join(dirname(fileURLToPath(import.meta.url)), "..", "print", "tr3k-get-qr.png");
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, png);
console.log(`wrote ${out}`);
