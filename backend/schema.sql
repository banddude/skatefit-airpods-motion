CREATE TABLE IF NOT EXISTS sessions (
  id TEXT PRIMARY KEY,
  device TEXT NOT NULL DEFAULT 'iPhone',
  started_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_seen TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  last_uptime REAL DEFAULT 0,
  sample_count INTEGER NOT NULL DEFAULT 0,
  event_count INTEGER NOT NULL DEFAULT 0,
  calibration_json TEXT DEFAULT NULL,
  diagnostics_json TEXT DEFAULT NULL,
  summary_json TEXT DEFAULT NULL,
  preferred_side TEXT DEFAULT 'left'
);
CREATE TABLE IF NOT EXISTS batches (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  batch_id TEXT UNIQUE,
  arrived_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  sample_count INTEGER NOT NULL,
  payload TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_batches_session_id ON batches(session_id, id);
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  event_start REAL,
  event_end REAL,
  confidence REAL,
  detail TEXT,
  event_source TEXT NOT NULL DEFAULT 'phone',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id, id);
CREATE TABLE IF NOT EXISTS labels (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  event_id INTEGER,
  label TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE IF NOT EXISTS settings (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  version INTEGER NOT NULL,
  rules_json TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
INSERT OR IGNORE INTO settings (id, version, rules_json) VALUES
(1, 1, '{"manualPitchDegrees":6,"minimumManualSeconds":0.45,"impactThresholdG":1.9,"rotationStartRate":2.6,"movementThresholdG":0.9,"maxCandidateSeconds":1.25}');
