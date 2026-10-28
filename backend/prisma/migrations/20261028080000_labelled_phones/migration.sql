-- AlterTable
ALTER TABLE "profiles" ADD COLUMN     "additional_phones" JSONB NOT NULL DEFAULT '[]',
ADD COLUMN     "phone_label" TEXT NOT NULL DEFAULT 'mobile';

-- AlterTable
ALTER TABLE "connections" ADD COLUMN     "additional_phones" JSONB NOT NULL DEFAULT '[]',
ADD COLUMN     "phone_label" TEXT NOT NULL DEFAULT 'mobile';
