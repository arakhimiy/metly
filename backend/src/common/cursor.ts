import { ApiError } from './api-error';

/** Opaque, URL-safe cursor around a per-user change sequence number (never a timestamp). */
export function encodeCursor(seq: bigint): string {
  return Buffer.from(`s:${seq.toString()}`, 'utf8').toString('base64url');
}

export function decodeCursor(cursor: string): bigint {
  const raw = Buffer.from(cursor, 'base64url').toString('utf8');
  const match = /^s:(\d{1,19})$/.exec(raw);
  if (!match?.[1]) throw new ApiError(410, 'cursor_expired', 'Unknown cursor; pull a full snapshot.');
  return BigInt(match[1]);
}

/** Offset cursors for plain list endpoints (`?cursor=&limit=`). */
export function encodeOffset(offset: number): string {
  return Buffer.from(`o:${offset}`, 'utf8').toString('base64url');
}

export function decodeOffset(cursor: string | undefined): number {
  if (!cursor) return 0;
  const match = /^o:(\d{1,9})$/.exec(Buffer.from(cursor, 'base64url').toString('utf8'));
  if (!match?.[1]) throw ApiError.badRequest('Invalid cursor.');
  return Number(match[1]);
}
