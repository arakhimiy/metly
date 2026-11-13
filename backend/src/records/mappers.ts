import type { Card, Connection, Event, FollowUp, Profile } from '../generated/prisma/client';
import { iso } from '../common/time';
import { connectionContacts, contactsToLegacy, profileContacts } from './contacts';
import {
  type CardDesign,
  type CardSnapshot,
  DEFAULT_NOTIFICATION_PREFS,
  DEFAULT_PRIVACY,
  type MeetingContext,
  NotificationPrefs,
  type PrivacySettings,
} from './wire';

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

/** A stored design → wire: `visibleContacts` only when the card has a selection (null/absent = legacy card). */
export function designToWire(design: unknown): CardDesign {
  const { visibleContacts, ...rest } = (design ?? {}) as CardDesign & { visibleContacts?: string[] | null };
  return Array.isArray(visibleContacts) ? { ...rest, visibleContacts } : rest;
}

export function snapshotToWire(snapshot: unknown): WireRecord | null {
  if (!snapshot) return null;
  const s = snapshot as CardSnapshot;
  return compact({ ...s, design: designToWire(s.design), url: s.url ?? null });
}

/**
 * The list and the legacy fields derived from it (a row from before the list reads as the list built
 * from its legacy columns), so every response carries both.
 */
export function profileToWire(p: Profile): WireRecord {
  const contacts = profileContacts(p);
  const legacy = contactsToLegacy(contacts);
  return compact({
    id: p.id,
    fullName: p.fullName,
    jobTitle: p.jobTitle,
    company: p.company,
    photoUrl: p.photoUrl,
    logoUrl: p.logoUrl,
    contactFields: legacy.contactFields,
    phoneLabel: legacy.phoneLabel,
    additionalPhones: legacy.additionalPhones,
    contacts,
    defaultCardId: p.defaultCardId,
    linksPaused: p.linksPaused,
    // Parse, not spread: stored JSON may still carry retired keys (the Telegram bot's `delivery`).
    notificationPrefs: NotificationPrefs.parse({ ...DEFAULT_NOTIFICATION_PREFS, ...(p.notificationPrefs as object) }),
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
    design: designToWire(c.design),
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
  const contacts = connectionContacts(c);
  const legacy = contactsToLegacy(contacts);
  const value = (kind: string) => legacy.contactFields.find((f) => f.kind === kind)?.value ?? '';
  return compact({
    id: c.id,
    remoteUserId: c.remoteUserId,
    fullName: c.fullName,
    jobTitle: c.jobTitle,
    company: c.company,
    phone: value('phone'),
    phoneLabel: legacy.phoneLabel,
    additionalPhones: legacy.additionalPhones,
    contacts,
    email: value('email'),
    telegram: value('telegram'),
    website: value('website'),
    linkedin: value('linkedin'),
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
