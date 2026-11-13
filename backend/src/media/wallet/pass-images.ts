import sharp from 'sharp';
import { hexString } from './pass-json';

/**
 * The Nameshake mark drawn as vector shapes (no fonts needed — slim container images have none):
 * a rounded square with an "N" in a 100×100 box.
 */
function markSvg(size: number, fill: string, ink: string): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 100 100">
  <rect x="0" y="0" width="100" height="100" rx="22" ry="22" fill="${fill}"/>
  <path d="M26 74V26h11l26 32V26h11v48H63L37 42v32z" fill="${ink}"/>
</svg>`;
}

async function png(svg: string): Promise<Buffer> {
  return sharp(Buffer.from(svg)).png({ compressionLevel: 9 }).toBuffer();
}

/** icon.png (29 pt) at 1×/2×/3× — shown in notifications and on the lock screen. */
export async function iconImages(): Promise<Record<string, Buffer>> {
  const [one, two, three] = await Promise.all([29, 58, 87].map((size) => png(markSvg(size, '#111114', '#ffffff'))));
  return { 'icon.png': one!, 'icon@2x.png': two!, 'icon@3x.png': three! };
}

/** logo.png (160×50 pt) at 1×/2×/3×: the mark on the left, transparent elsewhere, in pass colours. */
export async function logoImages(foreground: number, background: number): Promise<Record<string, Buffer>> {
  const render = async (scale: number) => {
    const height = 50 * scale;
    const mark = await png(markSvg(Math.round(height * 0.8), hexString(foreground), hexString(background)));
    return sharp({ create: { width: 160 * scale, height, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } })
      .composite([{ input: mark, top: Math.round(height * 0.1), left: 0 }])
      .png({ compressionLevel: 9 })
      .toBuffer();
  };
  const [one, two, three] = await Promise.all([1, 2, 3].map(render));
  return { 'logo.png': one!, 'logo@2x.png': two!, 'logo@3x.png': three! };
}
