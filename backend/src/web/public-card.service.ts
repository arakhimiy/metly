import { Inject, Injectable } from '@nestjs/common';
import { ENV, type Env } from '../config/env';
import type { Card, Profile } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { cardContactsView } from '../records/contacts';
import { cardUrl, designToWire } from '../records/mappers';
import { SLUG_PATTERN } from '../records/slug';
import { firstName } from '../records/snapshot';
import { type CardDesign, type ContactEntry, type ContactField, type LabeledPhone, type PhoneLabel, cardIdentity } from '../records/wire';
import { safeHttpUrl } from './html';

export type ResolvedCard =
  | { status: 'unknown'; slug: string }
  | { status: 'deleted'; slug: string }
  | { status: 'paused'; slug: string; card: Card }
  | { status: 'available'; slug: string; card: Card; profile: Profile };

/** What every public surface (page, vCard, JSON, Wallet) may show of an available card. */
export interface PublicView {
  slug: string;
  url: string;
  card: Card;
  /** The owner's profile with the card's switches applied (a hidden job title / company is blank). */
  profile: Profile;
  design: CardDesign;
  /** The card's selection ∩ Public, profile order — never Connections or Private. */
  contacts: ContactEntry[];
  /** Legacy: the first of each legacy kind among `contacts`, in kind order. */
  fields: ContactField[];
  /** Legacy: label of the phone in `fields`. */
  phoneLabel: PhoneLabel;
  /** Legacy: the phones of `contacts` after the first. */
  additionalPhones: LabeledPhone[];
  fullName: string;
  firstName: string;
  /** Only when the card shows the photo and it is an absolute http(s) URL. */
  photoUrl: string | null;
  logoUrl: string | null;
}

/** Lowercased slug if it matches the openapi `Slug` pattern, else null. */
export function normalizeSlug(raw: string | undefined | null): string | null {
  const slug = (raw ?? '').trim().toLowerCase();
  return slug.length > 0 && slug.length <= 40 && SLUG_PATTERN.test(slug) ? slug : null;
}

@Injectable()
export class PublicCardService {
  constructor(
    private readonly prisma: PrismaService,
    @Inject(ENV) private readonly env: Env,
  ) {}

  /**
   * - available: live card, live owner with a profile, links not paused;
   * - paused: `profile.linksPaused` (or no profile yet) — no personal data;
   * - deleted: the slug was issued but its card is tombstoned or gone (account deleted);
   * - unknown: never issued.
   */
  async resolve(rawSlug: string | undefined | null): Promise<ResolvedCard> {
    const slug = normalizeSlug(rawSlug);
    if (!slug) return { status: 'unknown', slug: (rawSlug ?? '').toLowerCase() };
    const card = await this.prisma.card.findUnique({
      where: { slug },
      include: { user: { select: { deletedAt: true, profile: true } } },
    });
    if (!card) {
      const issued = await this.prisma.slug.findUnique({ where: { slug }, select: { slug: true } });
      return issued ? { status: 'deleted', slug } : { status: 'unknown', slug };
    }
    const { user, ...row } = card;
    if (row.deletedAt || user.deletedAt) return { status: 'deleted', slug };
    const profile = user.profile;
    if (!profile || profile.deletedAt || profile.linksPaused) return { status: 'paused', slug, card: row };
    return { status: 'available', slug, card: row, profile };
  }

  view(resolved: Extract<ResolvedCard, { status: 'available' }>): PublicView {
    const { card, profile, slug } = resolved;
    const design = designToWire(card.design);
    const { contacts, fields, phoneLabel, additionalPhones } = cardContactsView(profile, design, 'public');
    return {
      slug,
      url: cardUrl(this.env.WEB_BASE_URL, slug),
      card,
      profile: { ...profile, ...cardIdentity(profile, design) },
      design,
      contacts,
      fields,
      phoneLabel,
      additionalPhones,
      fullName: profile.fullName,
      firstName: firstName(profile.fullName),
      photoUrl: design.showPhoto ? safeHttpUrl(profile.photoUrl) : null,
      logoUrl: design.showLogo ? safeHttpUrl(profile.logoUrl) : null,
    };
  }

  /** openapi `PublicCard` for the unauthenticated route: never `owner.userId` or `viewer`. */
  wire(resolved: ResolvedCard): Record<string, unknown> {
    if (resolved.status !== 'available') return { slug: resolved.slug, status: resolved.status };
    const v = this.view(resolved);
    return {
      slug: v.slug,
      status: 'available',
      url: v.url,
      cardName: v.card.name,
      owner: {
        fullName: v.fullName,
        firstName: v.firstName,
        jobTitle: v.profile.jobTitle,
        company: v.profile.company,
        ...(v.photoUrl ? { photoUrl: v.photoUrl } : {}),
      },
      design: v.design,
      fields: v.fields,
      phoneLabel: v.phoneLabel,
      additionalPhones: v.additionalPhones,
      contacts: v.contacts,
    };
  }
}
