import { type ArgumentsHost, Catch, type ExceptionFilter, HttpException, Logger } from '@nestjs/common';
import type { Response } from 'express';
import { ApiError, type ErrorCode } from './api-error';
import type { MetlyRequest } from './request';

const STATUS_CODES: Record<number, ErrorCode> = {
  400: 'invalid_request',
  401: 'unauthorized',
  403: 'forbidden',
  404: 'not_found',
  405: 'invalid_request',
  409: 'conflict',
  410: 'gone',
  413: 'payload_too_large',
  415: 'unsupported_media_type',
  422: 'validation_failed',
  429: 'rate_limited',
  503: 'service_unavailable',
};

/** Every non-2xx response carries the openapi `Error` body; 5xx messages never reach users. */
@Catch()
export class ErrorFilter implements ExceptionFilter {
  private readonly logger = new Logger('Errors');

  catch(exception: unknown, host: ArgumentsHost) {
    if (host.getType() !== 'http') return;
    const context = host.switchToHttp();
    const response = context.getResponse<Response>();
    const request = context.getRequest<MetlyRequest>();
    const requestId = (request as { id?: unknown }).id ? String((request as { id?: unknown }).id) : undefined;
    const error = this.toApiError(exception);

    if (error.status >= 500) {
      this.logger.error({ err: exception, requestId, path: request.path }, 'request failed');
    }
    if (response.headersSent) return;
    for (const [name, value] of Object.entries(error.headers ?? {})) response.setHeader(name, value);
    response.status(error.status).json(error.toBody(requestId));
  }

  private toApiError(exception: unknown): ApiError {
    if (exception instanceof ApiError) return exception;
    // Body parser errors (malformed JSON, body too large) arrive as plain errors with a status.
    const raw = exception as { status?: number; statusCode?: number; type?: string };
    if (raw && typeof raw === 'object' && (raw.type === 'entity.parse.failed' || raw.type === 'entity.too.large')) {
      return raw.type === 'entity.too.large'
        ? new ApiError(413, 'payload_too_large', 'The request body is too large.')
        : ApiError.badRequest('The request body is not valid JSON.');
    }
    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const code = STATUS_CODES[status] ?? (status >= 500 ? 'internal' : 'invalid_request');
      const message = status >= 500 ? 'Something went wrong on our side.' : exception.message;
      return new ApiError(status, code, message);
    }
    return new ApiError(500, 'internal', 'Something went wrong on our side.');
  }
}
