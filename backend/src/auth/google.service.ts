import { Inject, Injectable } from '@nestjs/common';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { ApiError } from '../common/api-error';
import { ENV, type Env } from '../config/env';

const googleKeys = createRemoteJWKSet(new URL('https://www.googleapis.com/oauth2/v3/certs'));

export interface GoogleIdentity {
  subject: string;
  email: string | null;
  name: string | null;
}

/** Google OpenID Connect id_token from the app's PKCE flow. */
@Injectable()
export class GoogleService {
  constructor(@Inject(ENV) private readonly env: Env) {}

  async verify(idToken: string, nonce: string | null | undefined): Promise<GoogleIdentity> {
    if (this.env.GOOGLE_CLIENT_IDS.length === 0) throw ApiError.unavailable('Sign in with Google is not configured.');
    let payload;
    try {
      ({ payload } = await jwtVerify(idToken, googleKeys, {
        issuer: ['accounts.google.com', 'https://accounts.google.com'],
        audience: this.env.GOOGLE_CLIENT_IDS,
      }));
    } catch {
      throw ApiError.unauthorized('The Google ID token is invalid.');
    }
    if (payload.email_verified !== true) throw ApiError.unauthorized('Your Google email address is not verified.');
    if (nonce && payload.nonce !== nonce) throw ApiError.unauthorized('The Google sign-in nonce does not match.');
    if (typeof payload.sub !== 'string') throw ApiError.unauthorized('The Google ID token is invalid.');
    return {
      subject: payload.sub,
      email: typeof payload.email === 'string' ? payload.email : null,
      name: typeof payload.name === 'string' ? payload.name : null,
    };
  }
}
