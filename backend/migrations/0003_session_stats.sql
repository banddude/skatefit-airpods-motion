-- One-time migration for the existing production database.
ALTER TABLE sessions ADD COLUMN summary_json TEXT DEFAULT NULL;
