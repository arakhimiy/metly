-- Contact list (docs/api/CONTACTS.md). Existing rows keep '[]' and are read as the list built from
-- their legacy columns until their next write.

-- AlterTable
ALTER TABLE "profiles" ADD COLUMN     "contacts" JSONB NOT NULL DEFAULT '[]';

-- AlterTable
ALTER TABLE "connections" ADD COLUMN     "contacts" JSONB NOT NULL DEFAULT '[]';
