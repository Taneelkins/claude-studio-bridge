/**
 * Minimal PNG -> RGBA8 decoder (no dependencies). Used for the no-API-key image
 * upload path, where Studio builds an EditableImage from raw pixels.
 *
 * Supports every non-interlaced PNG: greyscale, RGB, palette, grey+alpha, RGBA,
 * at bit depths 1-16 (16-bit is reduced to 8). Interlaced PNGs are rejected —
 * re-save them (e.g. `sips -s format png in.png --out out.png`).
 */
import zlib from "node:zlib";

export interface RgbaImage {
  width: number;
  height: number;
  /** width*height*4 bytes, row-major RGBA. */
  pixels: Buffer;
}

const SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const CHANNELS: Record<number, number> = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 };

export function isPng(data: Buffer): boolean {
  return data.length > 8 && data.subarray(0, 8).equals(SIGNATURE);
}

export function decodePng(data: Buffer): RgbaImage {
  if (!isPng(data)) throw new Error("Not a PNG file");

  let off = 8;
  let width = 0, height = 0, depth = 0, colorType = 0, interlace = 0;
  let palette: Buffer | undefined;
  let trns: Buffer | undefined;
  const idat: Buffer[] = [];

  while (off < data.length) {
    const len = data.readUInt32BE(off);
    const type = data.toString("latin1", off + 4, off + 8);
    const body = data.subarray(off + 8, off + 8 + len);
    off += 12 + len;
    if (type === "IHDR") {
      width = body.readUInt32BE(0);
      height = body.readUInt32BE(4);
      depth = body[8];
      colorType = body[9];
      interlace = body[12];
    } else if (type === "PLTE") palette = body;
    else if (type === "tRNS") trns = body;
    else if (type === "IDAT") idat.push(body);
    else if (type === "IEND") break;
  }

  if (interlace) throw new Error("Interlaced PNGs aren't supported; re-save without interlacing");
  const channels = CHANNELS[colorType];
  if (!channels) throw new Error(`Unsupported PNG color type ${colorType}`);

  const bitsPerPixel = channels * depth;
  const bpp = Math.max(1, bitsPerPixel >> 3); // bytes per pixel for filtering
  const stride = Math.ceil((width * bitsPerPixel) / 8);
  const raw = zlib.inflateSync(Buffer.concat(idat));

  // Undo per-row filters in place into `rows`.
  const rows = Buffer.alloc(stride * height);
  let prev = Buffer.alloc(stride);
  for (let y = 0; y < height; y++) {
    const filter = raw[y * (stride + 1)];
    const line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const out = rows.subarray(y * stride, (y + 1) * stride);
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? out[x - bpp] : 0;
      const b = prev[x];
      const c = x >= bpp ? prev[x - bpp] : 0;
      let v = line[x];
      switch (filter) {
        case 1: v += a; break;
        case 2: v += b; break;
        case 3: v += (a + b) >> 1; break;
        case 4: {
          const p = a + b - c;
          const pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c);
          v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
          break;
        }
      }
      out[x] = v & 0xff;
    }
    prev = out;
  }

  // Read one sample (channel value) scaled to 0-255.
  const sample = (row: Buffer, index: number): number => {
    if (depth === 8) return row[index];
    if (depth === 16) return row[index * 2];
    const bitPos = index * depth;
    const byte = row[bitPos >> 3];
    const shift = 8 - depth - (bitPos & 7);
    const v = (byte >> shift) & ((1 << depth) - 1);
    return colorType === 3 ? v : Math.round((v * 255) / ((1 << depth) - 1));
  };
  // Raw (unscaled) value — needed for palette indices and tRNS comparisons.
  const rawSample = (row: Buffer, index: number): number => {
    if (depth === 8) return row[index];
    if (depth === 16) return row.readUInt16BE(index * 2);
    const bitPos = index * depth;
    return (row[bitPos >> 3] >> (8 - depth - (bitPos & 7))) & ((1 << depth) - 1);
  };

  const pixels = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y++) {
    const row = rows.subarray(y * stride, (y + 1) * stride);
    for (let x = 0; x < width; x++) {
      const o = (y * width + x) * 4;
      let r: number, g: number, b: number, a = 255;
      if (colorType === 3) {
        const idx = rawSample(row, x);
        if (!palette) throw new Error("Palette PNG without PLTE chunk");
        r = palette[idx * 3]; g = palette[idx * 3 + 1]; b = palette[idx * 3 + 2];
        if (trns && idx < trns.length) a = trns[idx];
      } else if (colorType === 0 || colorType === 4) {
        r = g = b = sample(row, x * channels);
        if (colorType === 4) a = sample(row, x * channels + 1);
        else if (trns && rawSample(row, x) === trns.readUInt16BE(0)) a = 0;
      } else {
        r = sample(row, x * channels);
        g = sample(row, x * channels + 1);
        b = sample(row, x * channels + 2);
        if (colorType === 6) a = sample(row, x * channels + 3);
        else if (
          trns &&
          rawSample(row, x * 3) === trns.readUInt16BE(0) &&
          rawSample(row, x * 3 + 1) === trns.readUInt16BE(2) &&
          rawSample(row, x * 3 + 2) === trns.readUInt16BE(4)
        ) a = 0;
      }
      pixels[o] = r; pixels[o + 1] = g; pixels[o + 2] = b; pixels[o + 3] = a;
    }
  }
  return { width, height, pixels };
}
