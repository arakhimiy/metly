import { Inject, Injectable, Logger } from '@nestjs/common';
import {
  AppStoreServerAPIClient,
  Environment,
  type JWSRenewalInfoDecodedPayload,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from '@apple/app-store-server-library';
import { ApiError } from '../../common/api-error';
import { ENV, type Env } from '../../config/env';
import { appleRootCertificates } from './apple-roots';

export interface AppleSubscriptionStatus {
  status: number;
  transaction: JWSTransactionDecodedPayload;
  renewal?: JWSRenewalInfoDecodedPayload;
}

const LOCAL_ENVIRONMENTS: ReadonlySet<string> = new Set([Environment.XCODE, Environment.LOCAL_TESTING]);

/** Reads a JWS payload WITHOUT verifying it — only to choose the verifier that then checks it. */
function peek(jws: string): Record<string, unknown> {
  const part = jws.split('.')[1];
  if (!part) throw ApiError.badRequest('Malformed signed data.');
  try {
    const value = JSON.parse(Buffer.from(part, 'base64url').toString('utf8')) as unknown;
    if (value && typeof value === 'object') return value as Record<string, unknown>;
  } catch {
    // fall through
  }
  throw ApiError.badRequest('Malformed signed data.');
}

/**
 * Apple-facing side of subscriptions: JWS verification (`SignedDataVerifier`, chain to the vendored
 * Apple roots, bundle id, environment) and the App Store Server API.
 *
 * Environments accepted:
 * - `Production` when APP_STORE_ENVIRONMENT=Production;
 * - `Sandbox` always (App Review and TestFlight buy in the sandbox against the production server);
 * - `Xcode` / `LocalTesting` (StoreKit configuration files, signed locally by Xcode — the library
 *   skips the signature check for them) only when NODE_ENV is not production.
 * Bundle ids: any of APPLE_BUNDLE_IDS (release + debug); APPLE_BUNDLE_IDS[0] when the data names none.
 */
@Injectable()
export class AppStoreGateway {
  private readonly logger = new Logger(AppStoreGateway.name);
  private readonly verifiers = new Map<string, SignedDataVerifier>();
  private readonly clients = new Map<string, AppStoreServerAPIClient>();
  private roots: Buffer[] | undefined;

  constructor(@Inject(ENV) private readonly env: Env) {}

  /** App Store Server API credentials (issuer, key id, .p8). */
  get apiConfigured(): boolean {
    return Boolean(this.env.APP_STORE_ISSUER_ID && this.env.APP_STORE_KEY_ID && this.env.APP_STORE_PRIVATE_KEY);
  }

  isLocalEnvironment(environment: string): boolean {
    return LOCAL_ENVIRONMENTS.has(environment);
  }

  /** Whether data from `environment` may be accepted by this deployment at all. */
  acceptsEnvironment(environment: string): boolean {
    if (environment === Environment.PRODUCTION) return this.env.APP_STORE_ENVIRONMENT === 'Production';
    if (environment === Environment.SANDBOX) return true;
    if (this.isLocalEnvironment(environment)) return this.env.NODE_ENV !== 'production';
    return false;
  }

  /** StoreKit transaction from the app. */
  async verifyTransaction(jws: string): Promise<JWSTransactionDecodedPayload> {
    const { environment, bundleId } = this.target(peek(jws));
    return this.run(() => this.verifier(environment, bundleId).verifyAndDecodeTransaction(jws));
  }

  async verifyRenewalInfo(jws: string, environment: string, bundleId: string): Promise<JWSRenewalInfoDecodedPayload> {
    return this.run(() => this.verifier(environment, bundleId).verifyAndDecodeRenewalInfo(jws));
  }

  /** App Store Server Notification V2 `signedPayload`. */
  async verifyNotification(signedPayload: string): Promise<ResponseBodyV2DecodedPayload> {
    const payload = peek(signedPayload);
    const data = (payload.data ?? payload.summary ?? payload.appData ?? {}) as Record<string, unknown>;
    const { environment, bundleId } = this.target(data);
    if (environment === Environment.PRODUCTION && !this.env.APP_STORE_APP_APPLE_ID) {
      throw ApiError.unavailable('App Store notifications are not configured (APP_STORE_APP_APPLE_ID).');
    }
    return this.run(() => this.verifier(environment, bundleId).verifyAndDecodeNotification(signedPayload));
  }

  /**
   * Authoritative state of one subscription from `GET /inApps/v1/subscriptions/{transactionId}`.
   * Null when the API is not configured or the environment has no server API (Xcode).
   */
  async subscriptionStatus(originalTransactionId: string, environment: string, bundleId: string): Promise<AppleSubscriptionStatus | null> {
    if (!this.apiConfigured || this.isLocalEnvironment(environment)) return null;
    const response = await this.client(environment, bundleId).getAllSubscriptionStatuses(originalTransactionId);
    for (const group of response.data ?? []) {
      for (const item of group.lastTransactions ?? []) {
        if (item.originalTransactionId !== originalTransactionId || !item.signedTransactionInfo) continue;
        const transaction = await this.run(() => this.verifier(environment, bundleId).verifyAndDecodeTransaction(item.signedTransactionInfo!));
        const renewal = item.signedRenewalInfo ? await this.verifyRenewalInfo(item.signedRenewalInfo, environment, bundleId) : undefined;
        return { status: Number(item.status ?? 0), transaction, ...(renewal ? { renewal } : {}) };
      }
    }
    return null;
  }

  private target(data: Record<string, unknown>): { environment: string; bundleId: string } {
    const environment = typeof data.environment === 'string' ? data.environment : '';
    if (!this.acceptsEnvironment(environment)) {
      throw ApiError.badRequest(`Transactions from the ${environment || 'unknown'} environment are not accepted here.`);
    }
    const allowed = this.env.APPLE_BUNDLE_IDS;
    if (allowed.length === 0) throw ApiError.unavailable('Purchases are not configured (APPLE_BUNDLE_IDS).');
    const claimed = typeof data.bundleId === 'string' ? data.bundleId : '';
    // An unknown bundle id is verified against the primary one and therefore rejected.
    return { environment, bundleId: allowed.includes(claimed) ? claimed : allowed[0]! };
  }

  private verifier(environment: string, bundleId: string): SignedDataVerifier {
    const key = `${environment}|${bundleId}`;
    let verifier = this.verifiers.get(key);
    if (!verifier) {
      this.roots ??= appleRootCertificates();
      const appAppleId = this.env.APP_STORE_APP_APPLE_ID ? Number(this.env.APP_STORE_APP_APPLE_ID) : undefined;
      // Online checks (OCSP revocation, current-date validity) for Apple-signed data.
      verifier = new SignedDataVerifier(this.roots, !this.isLocalEnvironment(environment), environment as Environment, bundleId, appAppleId);
      this.verifiers.set(key, verifier);
    }
    return verifier;
  }

  private client(environment: string, bundleId: string): AppStoreServerAPIClient {
    const key = `${environment}|${bundleId}`;
    let client = this.clients.get(key);
    if (!client) {
      client = new AppStoreServerAPIClient(
        this.env.APP_STORE_PRIVATE_KEY!,
        this.env.APP_STORE_KEY_ID!,
        this.env.APP_STORE_ISSUER_ID!,
        bundleId,
        environment as Environment,
      );
      this.clients.set(key, client);
    }
    return client;
  }

  /** Verification failures → 400; Apple's OCSP being unreachable → 503 (the app retries). */
  private async run<T>(fn: () => Promise<T>): Promise<T> {
    try {
      return await fn();
    } catch (error) {
      if (error instanceof VerificationException) {
        this.logger.warn({ status: error.status, cause: error.cause?.message }, 'App Store signed data rejected');
        if (error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE) throw ApiError.unavailable('Could not reach Apple to verify the purchase. Try again shortly.');
        throw ApiError.badRequest('The purchase could not be verified.');
      }
      throw error;
    }
  }
}
