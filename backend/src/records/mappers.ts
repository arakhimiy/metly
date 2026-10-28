import type { Card, Connection, Event, FollowUp, Profile } from '../generated/prisma/client';
import { iso } from '../common/time';
import {
  type CardDesign,
  type CardSnapshot,
  type ContactField,
  DEFAULT_NOTIFICATION_PREFS,
  DEFAULT_PRIVACY,
  type MeetingContext,
  type NotificationPrefs,
  type PrivacySettings,
} from './wire';
import { storedPhoneLabel, storedPhones } from './phones';

// Database rows → wire JSON (docs/api/openapi.yaml). Optional members are omitted when null, except
// where the schema requires the key. URLs are never empty strings: Swift's URL decoding rejects them.

export type WireRecord = Record<string, unknown>;

function compact<T extends WireRecord>(value: T): T {
  for (const key of Object.keys(value)) {
    if (value[key] === null || value[key] === undefined) delete value[key];
  }
  return value;
}

/** MeetingContext as stored (JSON) → wire. Stored dates are ISO strings already. */
export function contextToWire(context: unknown): WireRecord {
  const c = (context ?? {}) as Record<string, unknown>;
  return compact({
    eventId: (c.eventId as string | null) ?? null,
    eventName: (c.eventName as string | null) ?? null,
    place: (c.place as string | null) ?? null,
    city: (c.city as string | null) ?? null,
    metAt: (c.metAt as string | undefined) ?? new Date(0).toISOString(),
  });
}

/** MeetingContext (parsed, with Date) → JSON for storage. */
export function contextToJson(context: MeetingContext): Record<string, unknown> {
  return {
    eventId: context.eventId,
    eventName: context.eventName,
    place: context.place,
    city: context.city,
    metAt: context.metAt.toISOString(),
  };
}

export function snapshotToWire(snapshot: unknown): WireRecord | null {
  if (!snapshot) return null;
  const s = snapshot as CardSnapshot;
  return compact({ ...s, url: s.url ?? null });
}

export function profileToWire(p: Profile): WireRecord {
  return compact({
    id: p.id,
    fullName: p.fullName,
    jobTitle: p.jobTitle,
    company: p.company,
    photoUrl: p.photoUrl,
    logoUrl: p.logoUrl,
    contactFields: p.contactFields as ContactField[],
    phoneLabel: storedPhoneLabel(p.phoneLabel),
    additionalPhones: storedPhones(p.additionalPhones),
    defaultCardId: p.defaultCardId,
    linksPaused: p.linksPaused,
    notificationPrefs: { ...DEFAULT_NOTIFICATION_PREFS, ...(p.notificationPrefs as NotificationPrefs) },
    privacySettings: { ...DEFAULT_PRIVACY, ...(p.privacySettings as PrivacySettings) },
    isSetupComplete: p.isSetupComplete,
    createdAt: iso(p.createdAt),
    updatedAt: iso(p.updatedAt),
    deletedAt: iso(p.deletedAt),
  });
}

export interface CardContext {
  webBaseUrl: string;
  linksPaused: boolean;
}

export function cardUrl(webBaseUrl: string, slug: string): string {
  return `${webBaseUrl.replace(/\/$/, '')}/c/${slug}`;
}

export function cardToWire(c: Card, ctx: CardContext): WireRecord {
  return compact({
    id: c.id,
    name: c.name,
    slug: c.slug,
    url: c.slug ? cardUrl(ctx.webBaseUrl, c.slug) : null,
    sortOrder: c.sortOrder,
    design: c.design as CardDesign,
    publishState: 'published',
    isReadOnly: c.isReadOnly,
    isPaused: ctx.linksPaused,
    stats: { views: c.views, saves: c.saves, shareBacks: c.shareBacks, scans: c.scans },
    createdAt: iso(c.createdAt),
    updatedAt: iso(c.updatedAt),
    deletedAt: iso(c.deletedAt),
  });
}

export function eventToWire(e: Event): WireRecord {
  return compact({
    id: e.id,
    name: e.name,
    place: e.place,
    city: e.city,
    startDate: iso(e.startDate),
    endDate: iso(e.endDate),
    cardId: e.cardId,
    status: e.status,
    calendarEventIdentifier: e.calendarEventIdentifier,
    endedAt: iso(e.endedAt),
    createdAt: iso(e.createdAt),
    updatedAt: iso(e.updatedAt),
    deletedAt: iso(e.deletedAt),
  });
}

export function connectionToWire(c: Connection): WireRecord {
  return compact({
    id: c.id,
    remoteUserId: c.remoteUserId,
    fullName: c.fullName,
    jobTitle: c.jobTitle,
    company: c.company,
    phone: c.phone,
    phoneLabel: storedPhoneLabel(c.phoneLabel),
    additionalPhones: storedPhones(c.additionalPhones),
    email: c.email,
    telegram: c.telegram,
    website: c.website,
    linkedin: c.linkedin,
    avatarUrl: c.avatarUrl,
    theirCard: snapshotToWire(c.theirCard),
    mySharedCardId: c.mySharedCardId,
    source: c.source,
    context: contextToWire(c.context),
    previousMeetings: ((c.previousMeetings as unknown[]) ?? []).map(contextToWire),
    eventId: c.eventId,
    note: c.note,
    tags: (c.tags as string[]) ?? [],
    isMerged: c.isMerged,
    isPendingMerge: c.isPendingMerge,
    isBlocked: c.isBlocked,
    createdAt: iso(c.createdAt),
    updatedAt: iso(c.updatedAt),
    deletedAt: iso(c.deletedAt),
  });
}

export function followUpToWire(f: FollowUp): WireRecord {
  return compact({
    id: f.id,
    connectionId: f.connectionId,
    title: f.title,
    channel: f.channel,
    dueAt: iso(f.dueAt),
    isDone: f.isDone,
    completedAt: iso(f.completedAt),
    createdAt: iso(f.createdAt),
    updatedAt: iso(f.updatedAt),
    deletedAt: iso(f.deletedAt),
  });
}
