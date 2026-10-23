import type { z } from 'zod';
import { ApiError } from './api-error';

/** Parses a request body/query with a zod schema; failures become 422 with field → reason. */
export function parse<S extends z.ZodType>(schema: S, value: unknown): z.infer<S> {
  const result = schema.safeParse(value);
  if (result.success) return result.data;
  throw ApiError.validation(zodDetails(result.error));
}

export function zodDetails(error: z.ZodError): Record<string, string> {
  const details: Record<string, string> = {};
  for (const issue of error.issues) {
    const path = issue.path.length > 0 ? issue.path.join('.') : 'body';
    details[path] ??= issue.message;
  }
  return details;
}
