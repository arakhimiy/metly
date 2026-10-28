import yazl from 'yazl';
import type { WireRecord } from '../../records/mappers';

/** One CSV cell (RFC 4180), with spreadsheet formula injection neutralised. */
export function csvCell(value: unknown): string {
  let text = value === null || value === undefined ? '' : String(value);
  // A leading = + - @ (or tab/CR) makes Excel/Sheets evaluate the cell. Phone numbers keep their "+".
  if (/^[=@\t\r]/.test(text) || (/^[+-]/.test(text) && !/^[+-][\d\s().-]*$/.test(text))) text = `'${text}`;
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

export const CONNECTIONS_CSV_HEADER = [
  'name',
  'title',
  'company',
  'phone',
  'other phones',
  'email',
  'telegram',
  'website',
  'linkedin',
  'met at',
  'event',
  'place',
  'city',
  'tags',
  'note',
] as const;

/** "work: +998 71 200 00 00; home: …" — the extra phones of a connection in one cell. */
function otherPhones(value: unknown): string {
  const phones = Array.isArray(value) ? (value as { label?: string; value?: string }[]) : [];
  return phones
    .filter((p) => typeof p.value === 'string' && p.value.trim())
    .map((p) => `${p.label ?? 'other'}: ${p.value!.trim()}`)
    .join('; ');
}

/** connections.csv from wire connections. */
export function connectionsCsv(connections: WireRecord[]): string {
  const rows = connections.map((c) => {
    const context = (c.context ?? {}) as Record<string, unknown>;
    return [
      c.fullName,
      c.jobTitle,
      c.company,
      c.phone,
      otherPhones(c.additionalPhones),
      c.email,
      c.telegram,
      c.website,
      c.linkedin,
      context.metAt,
      context.eventName,
      context.place,
      context.city,
      ((c.tags as string[] | undefined) ?? []).join('; '),
      c.note,
    ];
  });
  // BOM so Excel opens UTF-8 (Cyrillic names) correctly.
  return `﻿${[CONNECTIONS_CSV_HEADER, ...rows].map((row) => row.map(csvCell).join(',')).join('\r\n')}\r\n`;
}

export interface ArchiveEntry {
  name: string;
  body: Buffer | string;
}

/** Builds a ZIP in memory. */
export function zip(entries: ArchiveEntry[], mtime = new Date()): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const file = new yazl.ZipFile();
    const chunks: Buffer[] = [];
    file.outputStream.on('data', (chunk: Buffer) => chunks.push(chunk));
    file.outputStream.on('end', () => resolve(Buffer.concat(chunks)));
    file.outputStream.on('error', reject);
    for (const entry of entries) {
      file.addBuffer(typeof entry.body === 'string' ? Buffer.from(entry.body, 'utf8') : entry.body, entry.name, { mtime });
    }
    file.end();
  });
}
