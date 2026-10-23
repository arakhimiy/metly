import { createParamDecorator, type ExecutionContext, SetMetadata } from '@nestjs/common';
import type { Request } from 'express';

export interface AuthedUser {
  id: string;
  familyId: string;
}

export interface MetlyRequest extends Request {
  user?: AuthedUser;
}

export const IS_PUBLIC = 'metly:public';
/** Skips bearer authentication (auth, public web, webhooks, PassKit). */
export const Public = () => SetMetadata(IS_PUBLIC, true);

/** The authenticated user. Only valid on routes that are not @Public(). */
export const CurrentUser = createParamDecorator((_data: unknown, context: ExecutionContext): AuthedUser => {
  const request = context.switchToHttp().getRequest<MetlyRequest>();
  if (!request.user) throw new Error('CurrentUser used on a public route');
  return request.user;
});

/** Client IP as seen behind the platform's proxy (Express `trust proxy` is set in main.ts). */
export function clientIp(request: Request): string {
  return request.ip ?? request.socket.remoteAddress ?? 'unknown';
}
