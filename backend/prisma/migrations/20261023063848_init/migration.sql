-- CreateEnum
CREATE TYPE "AuthProvider" AS ENUM ('apple', 'google');

-- CreateEnum
CREATE TYPE "Plan" AS ENUM ('free', 'pro');

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "email" TEXT,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "deleted_at" TIMESTAMPTZ(3),
    "seq" BIGINT NOT NULL DEFAULT 0,
    "tombstone_floor_seq" BIGINT NOT NULL DEFAULT 0,
    "telegram_chat_id" TEXT,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "auth_identities" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "provider" "AuthProvider" NOT NULL,
    "subject" TEXT NOT NULL,
    "email" TEXT,
    "apple_refresh_token" TEXT,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "auth_identities_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "refresh_tokens" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "family_id" UUID NOT NULL,
    "token_hash" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expires_at" TIMESTAMPTZ(3) NOT NULL,
    "rotated_at" TIMESTAMPTZ(3),
    "revoked_at" TIMESTAMPTZ(3),

    CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "profiles" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "full_name" TEXT NOT NULL,
    "job_title" TEXT NOT NULL,
    "company" TEXT NOT NULL,
    "photo_url" TEXT,
    "logo_url" TEXT,
    "contact_fields" JSONB NOT NULL,
    "default_card_id" UUID,
    "links_paused" BOOLEAN NOT NULL,
    "notification_prefs" JSONB NOT NULL,
    "privacy_settings" JSONB NOT NULL,
    "is_setup_complete" BOOLEAN NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "deleted_at" TIMESTAMPTZ(3),
    "seq" BIGINT NOT NULL,

    CONSTRAINT "profiles_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cards" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "slug" TEXT,
    "sort_order" INTEGER NOT NULL,
    "design" JSONB NOT NULL,
    "is_read_only" BOOLEAN NOT NULL DEFAULT false,
    "views" INTEGER NOT NULL DEFAULT 0,
    "saves" INTEGER NOT NULL DEFAULT 0,
    "share_backs" INTEGER NOT NULL DEFAULT 0,
    "scans" INTEGER NOT NULL DEFAULT 0,
    "pass_auth_token" TEXT NOT NULL,
    "content_updated_at" TIMESTAMPTZ(3) NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "deleted_at" TIMESTAMPTZ(3),
    "seq" BIGINT NOT NULL,

    CONSTRAINT "cards_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "slugs" (
    "slug" TEXT NOT NULL,
    "card_id" UUID NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "slugs_pkey" PRIMARY KEY ("slug")
);

-- CreateTable
CREATE TABLE "events" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "place" TEXT NOT NULL,
    "city" TEXT NOT NULL,
    "start_date" TIMESTAMPTZ(3) NOT NULL,
    "end_date" TIMESTAMPTZ(3) NOT NULL,
    "card_id" UUID,
    "status" TEXT NOT NULL,
    "calendar_event_identifier" TEXT,
    "ended_at" TIMESTAMPTZ(3),
    "summary_sent_at" TIMESTAMPTZ(3),
    "created_at" TIMESTAMPTZ(3) NOT NULL,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "deleted_at" TIMESTAMPTZ(3),
    "seq" BIGINT NOT NULL,

    CONSTRAINT "events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "connections" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "remote_user_id" UUID,
    "full_name" TEXT NOT NULL,
    "job_title" TEXT NOT NULL,
    "company" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "telegram" TEXT NOT NULL,
    "website" TEXT NOT NULL,
    "linkedin" TEXT NOT NULL,
    "avatar_url" TEXT,
    "their_card" JSONB,
    "my_shared_card_id" UUID,
    "source" TEXT NOT NULL,
    "context" JSONB NOT NULL,
    "previous_meetings" JSONB NOT NULL,
    "event_id" UUID,
    "note" TEXT NOT NULL,
    "tags" JSONB NOT NULL,
    "is_merged" BOOLEAN NOT NULL,
    "is_pending_merge" BOOLEAN NOT NULL,
    "is_blocked" BOOLEAN NOT NULL,
    "is_mutual" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMPTZ(3) NOT NULL,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "deleted_at" TIMESTAMPTZ(3),
    "seq" BIGINT NOT NULL,

    CONSTRAINT "connections_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "connection_aliases" (
    "alias_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "survivor_id" UUID NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "connection_aliases_pkey" PRIMARY KEY ("alias_id")
);

-- CreateTable
CREATE TABLE "follow_ups" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "connection_id" UUID,
    "title" TEXT NOT NULL,
    "channel" TEXT NOT NULL,
    "due_at" TIMESTAMPTZ(3) NOT NULL,
    "is_done" BOOLEAN NOT NULL,
    "completed_at" TIMESTAMPTZ(3),
    "reminded_for_due_at" TIMESTAMPTZ(3),
    "created_at" TIMESTAMPTZ(3) NOT NULL,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "deleted_at" TIMESTAMPTZ(3),
    "seq" BIGINT NOT NULL,

    CONSTRAINT "follow_ups_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "connect_sessions" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "token" TEXT NOT NULL,
    "card_id" UUID NOT NULL,
    "event_id" UUID,
    "method" TEXT NOT NULL,
    "expires_at" TIMESTAMPTZ(3) NOT NULL,
    "ended_at" TIMESTAMPTZ(3),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "connect_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "connect_requests" (
    "id" UUID NOT NULL,
    "from_user_id" UUID NOT NULL,
    "to_user_id" UUID NOT NULL,
    "from_card_id" UUID NOT NULL,
    "to_card_id" UUID,
    "method" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "is_suppressed" BOOLEAN NOT NULL DEFAULT false,
    "event_id" UUID,
    "event_name" TEXT,
    "place" TEXT,
    "from_connection_id" UUID,
    "to_connection_id" UUID,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "responded_at" TIMESTAMPTZ(3),
    "expires_at" TIMESTAMPTZ(3) NOT NULL,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,
    "from_seq" BIGINT NOT NULL,
    "to_seq" BIGINT NOT NULL,
    "expiry_published_at" TIMESTAMPTZ(3),

    CONSTRAINT "connect_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "blocks" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "blocked_user_id" UUID,
    "connection_id" UUID,
    "full_name" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "blocks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "share_backs" (
    "id" UUID NOT NULL,
    "card_id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "connection_id" UUID,
    "created_connection" BOOLEAN NOT NULL DEFAULT false,
    "added_phone" TEXT,
    "added_telegram" TEXT,
    "removal_token_hash" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "removed_at" TIMESTAMPTZ(3),

    CONSTRAINT "share_backs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "card_visits" (
    "id" BIGSERIAL NOT NULL,
    "card_id" UUID NOT NULL,
    "visitor_hash" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "card_visits_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "deferred_clicks" (
    "id" UUID NOT NULL,
    "token" TEXT NOT NULL,
    "card_id" UUID NOT NULL,
    "owner_id" UUID NOT NULL,
    "event_name" TEXT,
    "ip_prefix" TEXT NOT NULL,
    "user_agent" TEXT NOT NULL,
    "locale" TEXT,
    "time_zone" TEXT,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "claimed_at" TIMESTAMPTZ(3),
    "claimed_install_id" TEXT,

    CONSTRAINT "deferred_clicks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "devices" (
    "user_id" UUID NOT NULL,
    "device_id" TEXT NOT NULL,
    "apns_token" TEXT NOT NULL,
    "apns_environment" TEXT NOT NULL,
    "app_version" TEXT NOT NULL,
    "os_version" TEXT NOT NULL,
    "locale" TEXT NOT NULL,
    "time_zone" TEXT NOT NULL,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "devices_pkey" PRIMARY KEY ("user_id","device_id")
);

-- CreateTable
CREATE TABLE "entitlements" (
    "user_id" UUID NOT NULL,
    "plan" "Plan" NOT NULL DEFAULT 'free',
    "product_id" TEXT,
    "original_transaction_id" TEXT,
    "expires_at" TIMESTAMPTZ(3),
    "will_renew" BOOLEAN NOT NULL DEFAULT false,
    "renews_at" TIMESTAMPTZ(3),
    "environment" TEXT,
    "is_in_billing_retry" BOOLEAN NOT NULL DEFAULT false,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "entitlements_pkey" PRIMARY KEY ("user_id")
);

-- CreateTable
CREATE TABLE "app_store_notifications" (
    "notification_uuid" TEXT NOT NULL,
    "notification_type" TEXT NOT NULL,
    "subtype" TEXT,
    "original_transaction_id" TEXT,
    "received_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "app_store_notifications_pkey" PRIMARY KEY ("notification_uuid")
);

-- CreateTable
CREATE TABLE "telegram_link_tokens" (
    "token_hash" TEXT NOT NULL,
    "user_id" UUID NOT NULL,
    "expires_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "telegram_link_tokens_pkey" PRIMARY KEY ("token_hash")
);

-- CreateTable
CREATE TABLE "pass_registrations" (
    "device_library_identifier" TEXT NOT NULL,
    "serial_number" TEXT NOT NULL,
    "push_token" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "pass_registrations_pkey" PRIMARY KEY ("device_library_identifier","serial_number")
);

-- CreateTable
CREATE TABLE "uploads" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "kind" TEXT NOT NULL,
    "object_key" TEXT NOT NULL,
    "content_type" TEXT NOT NULL,
    "byte_size" INTEGER NOT NULL,
    "expires_at" TIMESTAMPTZ(3) NOT NULL,
    "committed_at" TIMESTAMPTZ(3),
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "uploads_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "data_export_requests" (
    "id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "email" TEXT,
    "requested_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "completed_at" TIMESTAMPTZ(3),

    CONSTRAINT "data_export_requests_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "idempotency_records" (
    "scope" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "request_hash" TEXT NOT NULL,
    "status" INTEGER NOT NULL,
    "body" JSONB,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "idempotency_records_pkey" PRIMARY KEY ("scope","key")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_telegram_chat_id_key" ON "users"("telegram_chat_id");

-- CreateIndex
CREATE INDEX "auth_identities_user_id_idx" ON "auth_identities"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "auth_identities_provider_subject_key" ON "auth_identities"("provider", "subject");

-- CreateIndex
CREATE UNIQUE INDEX "refresh_tokens_token_hash_key" ON "refresh_tokens"("token_hash");

-- CreateIndex
CREATE INDEX "refresh_tokens_family_id_idx" ON "refresh_tokens"("family_id");

-- CreateIndex
CREATE INDEX "refresh_tokens_user_id_idx" ON "refresh_tokens"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "profiles_user_id_key" ON "profiles"("user_id");

-- CreateIndex
CREATE INDEX "profiles_user_id_seq_idx" ON "profiles"("user_id", "seq");

-- CreateIndex
CREATE UNIQUE INDEX "cards_slug_key" ON "cards"("slug");

-- CreateIndex
CREATE INDEX "cards_user_id_seq_idx" ON "cards"("user_id", "seq");

-- CreateIndex
CREATE INDEX "events_user_id_seq_idx" ON "events"("user_id", "seq");

-- CreateIndex
CREATE INDEX "events_status_end_date_idx" ON "events"("status", "end_date");

-- CreateIndex
CREATE INDEX "connections_user_id_seq_idx" ON "connections"("user_id", "seq");

-- CreateIndex
CREATE INDEX "connections_user_id_remote_user_id_idx" ON "connections"("user_id", "remote_user_id");

-- CreateIndex
CREATE INDEX "connections_remote_user_id_idx" ON "connections"("remote_user_id");

-- CreateIndex
CREATE INDEX "connection_aliases_user_id_idx" ON "connection_aliases"("user_id");

-- CreateIndex
CREATE INDEX "follow_ups_user_id_seq_idx" ON "follow_ups"("user_id", "seq");

-- CreateIndex
CREATE INDEX "follow_ups_is_done_due_at_idx" ON "follow_ups"("is_done", "due_at");

-- CreateIndex
CREATE UNIQUE INDEX "connect_sessions_token_key" ON "connect_sessions"("token");

-- CreateIndex
CREATE INDEX "connect_sessions_user_id_idx" ON "connect_sessions"("user_id");

-- CreateIndex
CREATE INDEX "connect_requests_from_user_id_from_seq_idx" ON "connect_requests"("from_user_id", "from_seq");

-- CreateIndex
CREATE INDEX "connect_requests_to_user_id_to_seq_idx" ON "connect_requests"("to_user_id", "to_seq");

-- CreateIndex
CREATE INDEX "connect_requests_status_expires_at_idx" ON "connect_requests"("status", "expires_at");

-- CreateIndex
CREATE INDEX "blocks_blocked_user_id_idx" ON "blocks"("blocked_user_id");

-- CreateIndex
CREATE UNIQUE INDEX "blocks_user_id_blocked_user_id_key" ON "blocks"("user_id", "blocked_user_id");

-- CreateIndex
CREATE INDEX "share_backs_card_id_created_at_idx" ON "share_backs"("card_id", "created_at");

-- CreateIndex
CREATE INDEX "card_visits_card_id_visitor_hash_type_created_at_idx" ON "card_visits"("card_id", "visitor_hash", "type", "created_at");

-- CreateIndex
CREATE INDEX "card_visits_created_at_idx" ON "card_visits"("created_at");

-- CreateIndex
CREATE UNIQUE INDEX "deferred_clicks_token_key" ON "deferred_clicks"("token");

-- CreateIndex
CREATE UNIQUE INDEX "deferred_clicks_claimed_install_id_key" ON "deferred_clicks"("claimed_install_id");

-- CreateIndex
CREATE INDEX "deferred_clicks_ip_prefix_created_at_idx" ON "deferred_clicks"("ip_prefix", "created_at");

-- CreateIndex
CREATE INDEX "devices_apns_token_idx" ON "devices"("apns_token");

-- CreateIndex
CREATE UNIQUE INDEX "entitlements_original_transaction_id_key" ON "entitlements"("original_transaction_id");

-- CreateIndex
CREATE INDEX "telegram_link_tokens_user_id_idx" ON "telegram_link_tokens"("user_id");

-- CreateIndex
CREATE INDEX "pass_registrations_serial_number_idx" ON "pass_registrations"("serial_number");

-- CreateIndex
CREATE INDEX "uploads_user_id_idx" ON "uploads"("user_id");

-- CreateIndex
CREATE INDEX "data_export_requests_user_id_idx" ON "data_export_requests"("user_id");

-- CreateIndex
CREATE INDEX "idempotency_records_created_at_idx" ON "idempotency_records"("created_at");

-- AddForeignKey
ALTER TABLE "auth_identities" ADD CONSTRAINT "auth_identities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "refresh_tokens" ADD CONSTRAINT "refresh_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "profiles" ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "cards" ADD CONSTRAINT "cards_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "events" ADD CONSTRAINT "events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "connections" ADD CONSTRAINT "connections_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "follow_ups" ADD CONSTRAINT "follow_ups_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "connect_sessions" ADD CONSTRAINT "connect_sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "blocks" ADD CONSTRAINT "blocks_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "devices" ADD CONSTRAINT "devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "entitlements" ADD CONSTRAINT "entitlements_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
