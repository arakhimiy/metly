import { type CanActivate, type ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ApiError } from '../common/api-error';
import { IS_PUBLIC, type MetlyRequest } from '../common/request';
import { TokensService } from './tokens.service';

/** Global: every route needs `Authorization: Bearer <accessToken>` unless marked @Public(). */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly tokens: TokensService,
  ) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    if (context.getType() !== 'http') return true;
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC, [context.getHandler(), context.getClass()]);
    if (isPublic) return true;
    const request = context.switchToHttp().getRequest<MetlyRequest>();
    const header = request.headers.authorization ?? '';
    const match = /^Bearer\s+(.+)$/i.exec(header);
    if (!match?.[1]) throw ApiError.unauthorized('Missing bearer token.');
    const claims = await this.tokens.verifyAccess(match[1]);
    request.user = { id: claims.userId, familyId: claims.familyId };
    return true;
  }
}
