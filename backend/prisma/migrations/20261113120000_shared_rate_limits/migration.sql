-- Rate-limit counters shared by every API instance (fixed windows, one row per budget key).
-- UNLOGGED: counters are disposable, so skip the WAL; a crash only resets the windows.
CREATE UNLOGGED TABLE "rate_limit_windows" (
    "key" TEXT NOT NULL,
    "count" INTEGER NOT NULL,
    "reset_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "rate_limit_windows_pkey" PRIMARY KEY ("key")
);

CREATE INDEX "rate_limit_windows_reset_at_idx" ON "rate_limit_windows"("reset_at");
