import sharp from 'sharp';

export type ImageKind = 'photo' | 'logo';
export const IMAGE_KINDS: readonly ImageKind[] = ['photo', 'logo'];

/** Longest side of a stored profile image. */
export const MAX_DIMENSION = 1024;
/** Decompression-bomb guard: refuse inputs above ~50 megapixels. */
const MAX_INPUT_PIXELS = 50_000_000;

export class UnsupportedImageError extends Error {}

export interface ProcessedImage {
  body: Buffer;
  contentType: 'image/jpeg' | 'image/webp';
  extension: 'jpg' | 'webp';
  width: number;
  height: number;
}

/** ISO-BMFF brands of HEIF/HEIC stills (bytes 8–11 after `ftyp`). */
export function isHeif(input: Buffer): boolean {
  if (input.length < 12 || input.toString('latin1', 4, 8) !== 'ftyp') return false;
  return ['heic', 'heix', 'hevc', 'hevx', 'heim', 'heis', 'mif1', 'msf1'].includes(input.toString('latin1', 8, 12));
}

/**
 * Re-encodes an uploaded image for public serving:
 * - honours the EXIF orientation (`rotate()`), then drops all metadata (EXIF, GPS, XMP, ICC — sharp
 *   writes none unless asked; pixels are converted to sRGB);
 * - fits inside 1024×1024 without upscaling;
 * - JPEG (white background) — except logos with transparency, which stay transparent as WebP.
 *
 * HEIC: the prebuilt sharp/libvips binaries ship libheif with AV1 (AVIF) only — HEVC-coded HEIC
 * cannot be decoded for patent reasons. Such uploads fail with UnsupportedImageError; the iOS app
 * converts to JPEG before uploading.
 */
export async function processImage(input: Buffer, kind: ImageKind): Promise<ProcessedImage> {
  let hasAlpha: boolean;
  try {
    const meta = await sharp(input, { limitInputPixels: MAX_INPUT_PIXELS }).metadata();
    if (!meta.format || !['jpeg', 'png', 'heif', 'webp'].includes(meta.format)) throw new Error(`format ${meta.format}`);
    hasAlpha = meta.hasAlpha === true;
  } catch {
    throw unsupported(input);
  }
  const keepAlpha = kind === 'logo' && hasAlpha;
  try {
    let pipeline = sharp(input, { limitInputPixels: MAX_INPUT_PIXELS, failOn: 'error' })
      .rotate()
      .resize({ width: MAX_DIMENSION, height: MAX_DIMENSION, fit: 'inside', withoutEnlargement: true });
    pipeline = keepAlpha
      ? pipeline.webp({ quality: 90, alphaQuality: 100 })
      : pipeline.flatten({ background: '#ffffff' }).jpeg({ quality: 85, mozjpeg: true });
    const { data, info } = await pipeline.toBuffer({ resolveWithObject: true });
    return keepAlpha
      ? { body: data, contentType: 'image/webp', extension: 'webp', width: info.width, height: info.height }
      : { body: data, contentType: 'image/jpeg', extension: 'jpg', width: info.width, height: info.height };
  } catch {
    throw unsupported(input);
  }
}

function unsupported(input: Buffer): UnsupportedImageError {
  return new UnsupportedImageError(
    isHeif(input)
      ? 'HEIC images can’t be processed yet. Convert the image to JPEG and try again.'
      : 'This image can’t be read. Use a JPEG or PNG.',
  );
}
