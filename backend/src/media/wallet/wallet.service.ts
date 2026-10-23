import { Inject, Injectable, Logger, type OnModuleInit } from '@nestjs/common';
import { PKPass } from 'passkit-generator';
import { ApiError } from '../../common/api-error';
import { ENV, type Env } from '../../config/env';
import type { Card, Profile } from '../../generated/prisma/client';
import type { CardDesign } from '../../records/wire';
import { iconImages, logoImages } from './pass-images';
import { buildPassJson, paletteColors } from './pass-json';

export const PKPASS_CONTENT_TYPE = 'application/vnd.apple.pkpass';

/** Signs Apple Wallet passes for cards with the Pass Type ID certificate (PASS_* settings). */
@Injectable()
export class WalletService implements OnModuleInit {
  private readonly logger = new Logger(WalletService.name);
  private icons: Promise<Record<string, Buffer>> | undefined;
  private readonly logos = new Map<string, Promise<Record<string, Buffer>>>();

  constructor(@Inject(ENV) private readonly env: Env) {}

  onModuleInit() {
    // Render the icon set once at startup (kept in memory).
    this.icons = iconImages();
    this.icons.catch((error: unknown) => this.logger.error({ err: error }, 'could not render pass icons'));
  }

  get isConfigured(): boolean {
    const e = this.env;
    return Boolean(e.PASS_TEAM_ID && e.PASS_CERT_PEM && e.PASS_KEY_PEM && e.PASS_WWDR_PEM);
  }

  get passTypeIdentifier(): string {
    return this.env.PASS_TYPE_IDENTIFIER;
  }

  get webServiceURL(): string {
    return `${this.env.API_BASE_URL.replace(/\/+$/, '')}/passkit`;
  }

  assertConfigured() {
    if (!this.isConfigured) throw ApiError.unavailable('Apple Wallet passes aren’t available right now. Try again later.');
  }

  passJson(card: Card, profile: Profile): Record<string, unknown> {
    return buildPassJson({
      card,
      profile,
      passTypeIdentifier: this.env.PASS_TYPE_IDENTIFIER,
      teamIdentifier: this.env.PASS_TEAM_ID ?? '',
      webServiceURL: this.webServiceURL,
      webBaseUrl: this.env.WEB_BASE_URL,
    });
  }

  /** The signed `.pkpass` bytes. */
  async render(card: Card, profile: Profile): Promise<Buffer> {
    this.assertConfigured();
    const colors = paletteColors(card.design as CardDesign);
    const logoKey = `${colors.foreground}:${colors.background}`;
    let logos = this.logos.get(logoKey);
    if (!logos) {
      logos = logoImages(colors.foreground, colors.background);
      this.logos.set(logoKey, logos);
    }
    this.icons ??= iconImages();
    const [icons, logoSet] = await Promise.all([this.icons, logos]);
    const pass = new PKPass(
      { ...icons, ...logoSet, 'pass.json': Buffer.from(JSON.stringify(this.passJson(card, profile))) },
      {
        wwdr: this.env.PASS_WWDR_PEM!,
        signerCert: this.env.PASS_CERT_PEM!,
        signerKey: this.env.PASS_KEY_PEM!,
        ...(this.env.PASS_KEY_PASSPHRASE ? { signerKeyPassphrase: this.env.PASS_KEY_PASSPHRASE } : {}),
      },
    );
    return pass.getAsBuffer();
  }
}
