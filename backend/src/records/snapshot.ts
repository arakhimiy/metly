import type { Card, Profile } from '../generated/prisma/client';
import { cardUrl } from './mappers';
import { type CardDesign, type ContactField, contactFieldKinds } from './wire';

/**
 * What a viewer may see of an owner's contact fields:
 * - `public`: anyone with the link (web page, vCard, Wallet, Nearby peers, unaccepted requests);
 * - `connections`: a viewer with an accepted, mutual connect;
 * - Private fields never leave the owner's devices.
 */
export type Audience = 'public' | 'connections';

/** Profile fields on a card: (Public | Connections per audience) ∩ visibleFields, non-empty, in kind order. */
export function visibleFields(profile: Pick<Profile, 'contactFields'>, design: CardDesign, audience: Audience): ContactField[] {
  const allowed = new Set(design.visibleFields);
  const fields = ((profile.contactFields as ContactField[] | null) ?? []).filter(
    (f) =>
      allowed.has(f.kind) &&
      f.value.trim().length > 0 &&
      (f.privacy === 'public' || (audience === 'connections' && f.privacy === 'connections')),
  );
  const order = new Map(contactFieldKinds.map((k, i) => [k, i]));
  return fields.sort((a, b) => (order.get(a.kind) ?? 0) - (order.get(b.kind) ?? 0));
}

export function firstName(fullName: string): string {
  return fullName.trim().split(/\s+/)[0] ?? fullName;
}

/** Frozen copy of someone's card as shared (openapi `CardSnapshot`). */
export function cardSnapshot(card: Card, profile: Profile, audience: Audience, webBaseUrl: string) {
  const design = card.design as CardDesign;
  return {
    cardName: card.name,
    design,
    fullName: profile.fullName,
    jobTitle: profile.jobTitle,
    company: profile.company,
    fields: visibleFields(profile, design, audience),
    ...(card.slug ? { url: cardUrl(webBaseUrl, card.slug) } : {}),
  };
}
