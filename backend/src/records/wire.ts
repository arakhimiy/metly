import { z } from 'zod';

// Wire schemas for docs/api/openapi.yaml. Optional members may be omitted or null; nulls are
// normalised to undefined/null as each record needs. Enum values are the exact wire strings.

/** ISO-8601 with or without fractional seconds, with Z or an offset. */
export const timestamp = z
  .string()
  .refine((s) => /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:?\d{2})$/.test(s) && !Number.isNaN(Date.parse(s)), {
    message: 'must be an ISO-8601 timestamp',
  })
  .transform((s) => new Date(s));

export const nullableTimestamp = timestamp.nullish().transform((v) => v ?? null);

/** Lowercased UUID (any version; the app sends v4). */
export const uuid = z
  .string()
  .regex(/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/, 'must be a UUID')
  .transform((s) => s.toLowerCase());

export const nullableUuid = uuid.nullish().transform((v) => v ?? null);
const nullableString = z.string().nullish().transform((v) => v ?? null);

export const contactFieldKinds = ['phone', 'email', 'telegram', 'website', 'linkedin'] as const;
export const ContactFieldKind = z.enum(contactFieldKinds);
export type ContactFieldKind = z.infer<typeof ContactFieldKind>;
export const FieldPrivacy = z.enum(['public', 'connections', 'private']);
export const CardTemplate = z.enum(['minimal', 'professional', 'modern', 'bold', 'gradient', 'split', 'terminal', 'stack', 'editorial']);
export const CardPalette = z.enum(['graphite', 'snow', 'ink', 'sand', 'ocean', 'ember']);
export const ConnectionSource = z.enum([
  'nearby',
  'tapPhones',
  'scanQR',
  'justMet',
  'webShareBack',
  'paper',
  'contactsCapture',
  'connectRequest',
  'deferredLink',
  'manual',
]);
export type ConnectionSource = z.infer<typeof ConnectionSource>;
export const FollowUpChannel = z.enum(['telegram', 'email', 'call']);
export const EventStatus = z.enum(['active', 'ended']);
export const ConnectMethod = z.enum(['nearby', 'tapPhones', 'scan', 'emailLookup', 'deferred']);
export type ConnectMethod = z.infer<typeof ConnectMethod>;
export const SyncRecordType = z.enum(['profile', 'card', 'event', 'connection', 'followUp', 'connectRequest']);
export type SyncRecordType = z.infer<typeof SyncRecordType>;

/** Templates and palettes only Pro may switch a card to. */
export const PRO_TEMPLATES = new Set(['editorial']);
export const PRO_PALETTES = new Set(['ocean', 'ember']);

export const ContactField = z.object({
  kind: ContactFieldKind,
  value: z.string().max(200),
  privacy: FieldPrivacy,
});
export type ContactField = z.infer<typeof ContactField>;

export const CardDesign = z.object({
  template: CardTemplate,
  palette: CardPalette,
  appearance: z.enum(['light', 'dark']),
  font: z.enum(['system', 'rounded', 'serif', 'mono']),
  alignment: z.enum(['leading', 'center']),
  density: z.enum(['minimal', 'balanced', 'detailed']),
  background: z.enum(['solid', 'gradient']),
  showQR: z.boolean(),
  showPhoto: z.boolean(),
  showLogo: z.boolean(),
  visibleFields: z.array(ContactFieldKind).transform((fields) => [...new Set(fields)]),
});
export type CardDesign = z.infer<typeof CardDesign>;

export const CardSnapshot = z.object({
  cardName: z.string(),
  design: CardDesign,
  fullName: z.string(),
  jobTitle: z.string(),
  company: z.string(),
  fields: z.array(ContactField),
  url: nullableString,
});
export type CardSnapshot = z.infer<typeof CardSnapshot>;

export const MeetingContext = z.object({
  eventId: nullableUuid,
  eventName: nullableString,
  place: nullableString,
  city: nullableString,
  metAt: timestamp,
});
export type MeetingContext = z.infer<typeof MeetingContext>;

export const NotificationPrefs = z.object({
  followUpReminders: z.boolean(),
  eventSummary: z.boolean(),
  delivery: z.enum(['push', 'telegramBot']),
  telegramLinked: z.boolean().optional(),
  connectRequests: z.boolean(),
  cardSaved: z.boolean(),
  weeklySummary: z.boolean(),
  productNews: z.boolean(),
});
export type NotificationPrefs = z.infer<typeof NotificationPrefs>;

export const PrivacySettings = z.object({
  findByEmail: z.boolean(),
  showInNearby: z.boolean(),
  shareAnalytics: z.boolean(),
});
export type PrivacySettings = z.infer<typeof PrivacySettings>;

export const DEFAULT_NOTIFICATION_PREFS: NotificationPrefs = {
  followUpReminders: true,
  eventSummary: true,
  delivery: 'push',
  telegramLinked: false,
  connectRequests: true,
  cardSaved: true,
  weeklySummary: false,
  productNews: false,
};

export const DEFAULT_PRIVACY: PrivacySettings = { findByEmail: true, showInNearby: true, shareAnalytics: true };

const syncFields = {
  id: uuid,
  createdAt: timestamp,
  updatedAt: timestamp,
  deletedAt: nullableTimestamp,
};

export const ProfileIn = z.object({
  ...syncFields,
  fullName: z.string().max(80),
  jobTitle: z.string().max(80),
  company: z.string().max(80),
  contactFields: z.array(ContactField),
  defaultCardId: nullableUuid,
  linksPaused: z.boolean(),
  notificationPrefs: NotificationPrefs,
  privacySettings: PrivacySettings,
  isSetupComplete: z.boolean(),
});
export type ProfileIn = z.infer<typeof ProfileIn>;

export const CardIn = z.object({
  ...syncFields,
  name: z.string().max(40),
  sortOrder: z.number().int(),
  design: CardDesign,
});
export type CardIn = z.infer<typeof CardIn>;

export const EventIn = z.object({
  ...syncFields,
  name: z.string().max(80),
  place: z.string().max(200),
  city: z.string().max(120),
  startDate: timestamp,
  endDate: timestamp,
  cardId: nullableUuid,
  status: EventStatus,
  calendarEventIdentifier: nullableString,
  endedAt: nullableTimestamp,
});
export type EventIn = z.infer<typeof EventIn>;

export const ConnectionIn = z.object({
  ...syncFields,
  remoteUserId: nullableUuid,
  fullName: z.string().max(200),
  jobTitle: z.string().max(200),
  company: z.string().max(200),
  phone: z.string().max(200),
  email: z.string().max(200),
  telegram: z.string().max(200),
  website: z.string().max(500),
  linkedin: z.string().max(500),
  theirCard: CardSnapshot.nullish().transform((v) => v ?? null),
  mySharedCardId: nullableUuid,
  source: ConnectionSource,
  context: MeetingContext,
  previousMeetings: z.array(MeetingContext).max(200),
  eventId: nullableUuid,
  note: z.string().max(10_000),
  tags: z.array(z.string().max(40)).max(50),
  isMerged: z.boolean(),
  isPendingMerge: z.boolean(),
  isBlocked: z.boolean(),
});
export type ConnectionIn = z.infer<typeof ConnectionIn>;

export const FollowUpIn = z.object({
  ...syncFields,
  connectionId: nullableUuid,
  title: z.string().max(200),
  channel: FollowUpChannel,
  dueAt: timestamp,
  isDone: z.boolean(),
  completedAt: nullableTimestamp,
});
export type FollowUpIn = z.infer<typeof FollowUpIn>;

export const TombstoneIn = z.object({
  type: SyncRecordType,
  id: uuid,
  deletedAt: timestamp,
});
export type TombstoneIn = z.infer<typeof TombstoneIn>;
