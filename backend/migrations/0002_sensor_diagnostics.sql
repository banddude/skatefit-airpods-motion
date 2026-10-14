-- Apply this once to the existing production D1 database (schema.sql CREATE IF NOT EXISTS
-- does not add columns to already-existing tables).
ALTER TABLE sessions ADD COLUMN diagnostics_json TEXT DEFAULT NULL;
