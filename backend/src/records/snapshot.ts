import type { Card, Profile } from '../generated/prisma/client';
import { type Audience, cardContactsView, type ProfileContactColumns } from './contacts';
import { cardUrl, designToWire } from './mappers';
import { type CardDesign, type ContactField, cardIdentity } from './wire';

/**
 * What a viewer may see of an owner's contact entries:
 * - `public`: anyone with the link (web page, vCard, Wallet, Nearby peers, unaccepted requests);
 * - `connections`: a viewer with an accepted, mutual connect;
 * - Private entries never leave the owner's devices.
 */
export type { Audience };

/** Legacy `fields` of a card: the first visible entry of each legacy kind, in kind order (see `cardContactsView`). */
export function visibleFields(profile: ProfileContactColumns, design: CardDesign, audience: Audience): ContactField[] {
  return cardContactsView(profile, design, audience).fields;
}

export function firstName(fullName: string): string {
  return fullName.trim().split(/\s+/)[0] ?? fullName;
}

/** Frozen copy of someone's card as shared (openapi `CardSnapshot`). */
export function cardSnapshot(card: Card, profile: Profile, audience: Audience, webBaseUrl: string) {
  const design = card.design as CardDesign;
  return {
    cardName: card.name,
    design: designToWire(design),
    fullName: profile.fullName,
    ...cardIdentity(profile, design),
    fields: visibleFields(profile, design, audience),
    ...(card.slug ? { url: cardUrl(webBaseUrl, card.slug) } : {}),
  };
}
