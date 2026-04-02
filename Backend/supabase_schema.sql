-- ============================================================
-- Aarogyan — Supabase Database Schema
-- Run this in your Supabase SQL Editor (in order)
-- ============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ────────────────────────────────────────────────────────────
-- 1. USERS
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           TEXT UNIQUE NOT NULL,
    password_hash   TEXT NOT NULL,
    full_name       TEXT NOT NULL,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users (email);

-- ────────────────────────────────────────────────────────────
-- 2. PROFILES
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS profiles (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                 UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Section 1: Personal
    full_name               TEXT,
    date_of_birth           DATE,
    biological_sex          TEXT CHECK (biological_sex IN ('Male', 'Female', 'Intersex')),
    height_cm               NUMERIC(5,1),
    weight_kg               NUMERIC(5,1),
    blood_group             TEXT,
    city                    TEXT,
    region_state            TEXT,
    preferred_language      TEXT DEFAULT 'English',
    emergency_contact_name  TEXT,
    emergency_contact_phone TEXT,

    -- Sections 2–9: stored as JSONB arrays/objects
    existing_conditions     JSONB DEFAULT '[]'::JSONB,
    allergies               JSONB DEFAULT '[]'::JSONB,
    current_medications     JSONB DEFAULT '[]'::JSONB,
    supplements             JSONB DEFAULT '[]'::JSONB,
    past_medical_history    JSONB DEFAULT '[]'::JSONB,
    family_medical_history  JSONB DEFAULT '[]'::JSONB,
    lifestyle               JSONB DEFAULT '{}'::JSONB,
    mental_health           JSONB DEFAULT '{}'::JSONB,

    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_profiles_user_id ON profiles (user_id);

-- ────────────────────────────────────────────────────────────
-- 3. CONSULTATIONS
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS consultations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    start_date  DATE,
    notes       TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_consultations_user_id ON consultations (user_id);

-- ────────────────────────────────────────────────────────────
-- 4. SESSIONS
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sessions (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    consultation_id     UUID NOT NULL REFERENCES consultations(id) ON DELETE CASCADE,
    visit_date          DATE NOT NULL,
    symptoms            TEXT,
    diagnosis           TEXT,
    medications         TEXT,
    doctor_notes        TEXT,
    created_at          TIMESTAMPTZ DEFAULT NOW(),
    updated_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_sessions_consultation_id ON sessions (consultation_id);

-- ────────────────────────────────────────────────────────────
-- 5. SESSION DOCUMENTS
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS session_documents (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    file_name       TEXT NOT NULL,
    storage_path    TEXT NOT NULL,
    public_url      TEXT,
    content_type    TEXT,
    ocr_text        TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_session_documents_session_id ON session_documents (session_id);

-- ────────────────────────────────────────────────────────────
-- 6. CONVERSATIONS (Medical Assistant)
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS conversations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title       TEXT DEFAULT 'New Conversation',
    preview     TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_conversations_user_id ON conversations (user_id);

-- ────────────────────────────────────────────────────────────
-- 7. MESSAGES
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS messages (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id     UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    role                TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
    content             TEXT NOT NULL,
    created_at          TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_messages_conversation_id ON messages (conversation_id);

-- ────────────────────────────────────────────────────────────
-- 8. EMOTIONAL SESSIONS (Orbz / Buddy)
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS emotional_sessions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_text       TEXT,
    buddy_text      TEXT,
    mood_score      SMALLINT CHECK (mood_score BETWEEN 1 AND 10),
    emotion         TEXT,
    session_group_id UUID,
    emotion_probs   JSONB,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_emotional_sessions_user_id ON emotional_sessions (user_id);
CREATE INDEX idx_emotional_sessions_created_at ON emotional_sessions (created_at);
CREATE INDEX idx_emotional_sessions_group ON emotional_sessions (session_group_id);

-- ────────────────────────────────────────────────────────────
-- 9. STORAGE BUCKETS (run separately or via Supabase dashboard)
-- ────────────────────────────────────────────────────────────
-- Create a storage bucket called "documents" with:
--   Public: false (files accessed via signed URLs or backend proxy)
--   Max file size: 2097152 (2 MB)
--   Allowed MIME types: image/jpeg, image/png, application/pdf
--
-- Run this if the Supabase storage API supports SQL:
-- INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
-- VALUES (
--     'documents',
--     'documents',
--     true,
--     2097152,
--     ARRAY['image/jpeg', 'image/png', 'application/pdf']
-- )
-- ON CONFLICT (id) DO NOTHING;

-- ────────────────────────────────────────────────────────────
-- 10. UPDATED_AT TRIGGERS
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_profiles_updated_at
    BEFORE UPDATE ON profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_consultations_updated_at
    BEFORE UPDATE ON consultations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_sessions_updated_at
    BEFORE UPDATE ON sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_conversations_updated_at
    BEFORE UPDATE ON conversations
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ────────────────────────────────────────────────────────────
-- 11. ROW LEVEL SECURITY (RLS) — Disable for service role key
-- ────────────────────────────────────────────────────────────
-- Since the backend uses the SERVICE ROLE key (bypasses RLS),
-- RLS is disabled. Enable RLS policies only if you switch to
-- the ANON key on the backend.
ALTER TABLE users DISABLE ROW LEVEL SECURITY;
ALTER TABLE profiles DISABLE ROW LEVEL SECURITY;
ALTER TABLE consultations DISABLE ROW LEVEL SECURITY;
ALTER TABLE sessions DISABLE ROW LEVEL SECURITY;
ALTER TABLE session_documents DISABLE ROW LEVEL SECURITY;
ALTER TABLE conversations DISABLE ROW LEVEL SECURITY;
ALTER TABLE messages DISABLE ROW LEVEL SECURITY;
ALTER TABLE emotional_sessions DISABLE ROW LEVEL SECURITY;

-- ────────────────────────────────────────────────────────────
-- 12. MIGRATION: Add emotion detection columns
-- ────────────────────────────────────────────────────────────
-- Run this if you already have the emotional_sessions table:
--
-- ALTER TABLE emotional_sessions ADD COLUMN IF NOT EXISTS session_group_id UUID;
-- ALTER TABLE emotional_sessions ADD COLUMN IF NOT EXISTS emotion_probs JSONB;
-- CREATE INDEX IF NOT EXISTS idx_emotional_sessions_group ON emotional_sessions (session_group_id);
