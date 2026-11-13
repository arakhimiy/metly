/** Wire error codes (openapi `ErrorCode`). */
export type ErrorCode =
  | 'invalid_request'
  | 'validation_failed'
  | 'unauthorized'
  | 'token_expired'
  | 'invalid_grant'
  | 'forbidden'
  | 'not_found'
  | 'conflict'
  | 'gone'
  | 'cursor_expired'
  | 'plan_limit_reached'
  | 'pro_required'
  | 'rate_limited'
  | 'idempotency_conflict'
  | 'payload_too_large'
  | 'unsupported_media_type'
  | 'peer_unavailable'
  | 'request_expired'
  | 'blocked'
  | 'internal'
  | 'service_unavailable';

/** Thrown anywhere; the global filter turns it into the `Error` body. */
export class ApiError extends Error {
  constructor(
    readonly status: number,
    readonly code: ErrorCode,
    message: string,
    readonly details?: Record<string, string>,
    readonly headers?: Record<string, string>,
  ) {
    super(message);
  }

  /** The wire shape, also used for per-record errors in sync push results. */
  toBody(requestId?: string) {
    return {
      code: this.code,
      message: this.message,
      ...(requestId ? { requestId } : {}),
      ...(this.details ? { details: this.details } : {}),
    };
  }

  static badRequest(message: string, details?: Record<string, string>) {
    return new ApiError(400, 'invalid_request', message, details);
  }
  static validation(details: Record<string, string>, message = 'Validation failed.') {
    return new ApiError(422, 'validation_failed', message, details);
  }
  static unauthorized(message = 'Sign in again.', code: ErrorCode = 'unauthorized') {
    return new ApiError(401, code, message);
  }
  static forbidden(message = 'Not allowed.') {
    return new ApiError(403, 'forbidden', message);
  }
  static notFound(message = 'Not found.') {
    return new ApiError(404, 'not_found', message);
  }
  static gone(message = 'This record was deleted.') {
    return new ApiError(410, 'gone', message);
  }
  static planLimit(limit: 'cards' | 'openFollowUps' | 'activeEvents', message: string) {
    return new ApiError(403, 'plan_limit_reached', message, { limit });
  }
  static proRequired(message = 'This needs Nameshake Pro.') {
    return new ApiError(403, 'pro_required', message);
  }
  static unavailable(message: string) {
    return new ApiError(503, 'service_unavailable', message);
  }
}
