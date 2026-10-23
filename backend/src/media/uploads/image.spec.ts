import sharp from 'sharp';
import { describe, expect, it } from 'vitest';
import { isHeif, MAX_DIMENSION, processImage, UnsupportedImageError } from './image';

const jpegWithExif = () =>
  sharp({ create: { width: 2000, height: 1500, channels: 3, background: { r: 200, g: 40, b: 40 } } })
    .withMetadata({ orientation: 6 })
    .withExif({ IFD0: { Copyright: 'Secret Owner', Software: 'Camera' }, IFD3: { GPSLatitudeRef: 'N', GPSLatitude: '41/1 18/1 0/1' } })
    .jpeg()
    .toBuffer();

describe('processImage', () => {
  it('honours orientation, fits 1024 px and strips EXIF/GPS', async () => {
    const input = await jpegWithExif();
    const before = await sharp(input).metadata();
    expect(before.exif).toBeDefined();
    expect(before.orientation).toBe(6);

    const out = await processImage(input, 'photo');
    expect(out.contentType).toBe('image/jpeg');
    const meta = await sharp(out.body).metadata();
    expect(meta.format).toBe('jpeg');
    // Rotated 90° (portrait) and scaled to fit.
    expect(meta.height).toBe(MAX_DIMENSION);
    expect(meta.width).toBe(768);
    expect(meta.exif).toBeUndefined();
    expect(meta.orientation).toBeUndefined();
    expect(out.body.includes(Buffer.from('Secret Owner'))).toBe(false);
  });

  it('keeps transparency of logos as WebP, flattens photos to JPEG', async () => {
    const png = await sharp({ create: { width: 300, height: 100, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } }).png().toBuffer();
    const logo = await processImage(png, 'logo');
    expect(logo.contentType).toBe('image/webp');
    expect((await sharp(logo.body).metadata()).hasAlpha).toBe(true);
    const photo = await processImage(png, 'photo');
    expect(photo.contentType).toBe('image/jpeg');
  });

  it('rejects unreadable data and explains HEIC', async () => {
    await expect(processImage(Buffer.from('not an image at all'), 'photo')).rejects.toBeInstanceOf(UnsupportedImageError);
    const fakeHeic = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypheic'), Buffer.alloc(64)]);
    expect(isHeif(fakeHeic)).toBe(true);
    await expect(processImage(fakeHeic, 'photo')).rejects.toThrow(/HEIC/);
  });
});
