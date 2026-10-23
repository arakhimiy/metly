import { Body, Controller, Delete, HttpCode, Param, Post, Put } from '@nestjs/common';
import { z } from 'zod';
import { ApiError } from '../../common/api-error';
import { type AuthedUser, CurrentUser } from '../../common/request';
import { parse } from '../../common/validate';
import { IMAGE_KINDS, type ImageKind } from './image';
import { MAX_UPLOAD_BYTES, UPLOAD_CONTENT_TYPES, UploadsService } from './uploads.service';

const TicketBody = z.object({
  contentType: z.string().min(1).max(100),
  byteSize: z.number().int().positive(),
});
const CommitBody = z.object({ uploadId: z.string().min(1).max(100) });

function imageKind(value: string): ImageKind {
  if (!(IMAGE_KINDS as readonly string[]).includes(value)) throw ApiError.notFound('Unknown image kind.');
  return value as ImageKind;
}

/** Profile photo and company logo: presigned upload → commit (re-encode, strip metadata) → delete. */
@Controller('v1/me/profile')
export class UploadsController {
  constructor(private readonly uploads: UploadsService) {}

  @Post(':kind/upload')
  @HttpCode(200)
  async ticket(@CurrentUser() user: AuthedUser, @Param('kind') kind: string, @Body() body: unknown) {
    const imageKindValue = imageKind(kind);
    const input = parse(TicketBody, body);
    const contentType = input.contentType.toLowerCase();
    if (!(UPLOAD_CONTENT_TYPES as readonly string[]).includes(contentType)) {
      throw new ApiError(415, 'unsupported_media_type', 'Use a JPEG, PNG or HEIC image.');
    }
    if (input.byteSize > MAX_UPLOAD_BYTES) {
      throw new ApiError(413, 'payload_too_large', `Images can be at most ${MAX_UPLOAD_BYTES / 1_000_000} MB.`);
    }
    return this.uploads.ticket(user.id, imageKindValue, contentType, input.byteSize);
  }

  @Put(':kind')
  commit(@CurrentUser() user: AuthedUser, @Param('kind') kind: string, @Body() body: unknown) {
    const imageKindValue = imageKind(kind);
    const { uploadId } = parse(CommitBody, body);
    return this.uploads.commit(user.id, imageKindValue, uploadId);
  }

  @Delete(':kind')
  remove(@CurrentUser() user: AuthedUser, @Param('kind') kind: string) {
    return this.uploads.remove(user.id, imageKind(kind));
  }
}
