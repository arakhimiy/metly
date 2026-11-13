-- Telegram is now a sign-in provider (Log In with Telegram, OIDC) instead of a reminders bot.

-- Sign-in provider.
ALTER TYPE "AuthProvider" ADD VALUE 'telegram';

-- Retire the reminders bot: chat links and one-time link tokens.
DROP TABLE "telegram_link_tokens";
DROP INDEX "users_telegram_chat_id_key";
ALTER TABLE "users" DROP COLUMN "telegram_chat_id";

-- Profiles no longer carry the bot's delivery choice or link state.
UPDATE "profiles"
SET "notification_prefs" = "notification_prefs" - 'delivery' - 'telegramLinked'
WHERE "notification_prefs" ?| ARRAY['delivery', 'telegramLinked'];
