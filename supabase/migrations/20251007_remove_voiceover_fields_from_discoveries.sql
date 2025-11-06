-- Remove legacy voiceover columns now that playback derives storage paths directly.
-- Safe to re-run: each column drop guards with IF EXISTS.

BEGIN;

ALTER TABLE discoveries
    DROP COLUMN IF EXISTS voiceover_url,
    DROP COLUMN IF EXISTS voiceover_duration,
    DROP COLUMN IF EXISTS voice_model;

COMMIT;
