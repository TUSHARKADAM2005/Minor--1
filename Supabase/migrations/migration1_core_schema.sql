-- gen_random_uuid() is built in (Postgres 13+), so uuid-ossp isn't needed

CREATE TYPE interview_status    AS ENUM ('scheduled','in_progress','completed','evaluated');
CREATE TYPE question_difficulty AS ENUM ('quick_check','intermediate','advanced');
CREATE TYPE answer_status       AS ENUM ('uploaded','transcribed','evaluated','failed');

-- 1. Candidates (1:1 with auth.users)
CREATE TABLE candidates (
  id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name  VARCHAR(100) NOT NULL,
  email      VARCHAR(255) UNIQUE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. Question bank (admin-only: contains the rubric)
CREATE TABLE questions (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  question_text          TEXT NOT NULL,
  topic                  VARCHAR(60),
  difficulty             question_difficulty NOT NULL,
  time_limit_seconds     INT NOT NULL CHECK (time_limit_seconds BETWEEN 10 AND 180),
  expected_keywords      TEXT[] NOT NULL DEFAULT '{}',
  ideal_response_summary TEXT,
  is_active              BOOLEAN NOT NULL DEFAULT TRUE,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Interview sessions
CREATE TABLE interview_sessions (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id   UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  position_title VARCHAR(100) NOT NULL,
  status         interview_status NOT NULL DEFAULT 'scheduled',
  total_score    NUMERIC(5,2) CHECK (total_score BETWEEN 0 AND 100),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at     TIMESTAMPTZ,
  completed_at   TIMESTAMPTZ
);

-- 4. Which questions each session got, and in what order
CREATE TABLE session_questions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  UUID NOT NULL REFERENCES interview_sessions(id) ON DELETE CASCADE,
  question_id UUID NOT NULL REFERENCES questions(id) ON DELETE RESTRICT,
  position    INT  NOT NULL CHECK (position > 0),
  UNIQUE (session_id, question_id),
  UNIQUE (session_id, position)
);

-- 5. Answers and evaluation
CREATE TABLE session_answers (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id               UUID NOT NULL,
  question_id              UUID NOT NULL,
  audio_storage_path       TEXT,
  transcript               TEXT,
  technical_accuracy_score INT CHECK (technical_accuracy_score BETWEEN 0 AND 10),
  communication_score      INT CHECK (communication_score BETWEEN 0 AND 10),
  feedback                 TEXT,
  gaps                     TEXT[],
  duration_seconds         INT CHECK (duration_seconds >= 0),
  status                   answer_status NOT NULL DEFAULT 'uploaded',
  error_message            TEXT,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (session_id, question_id),
  -- an answer must belong to a question assigned to that session
  FOREIGN KEY (session_id, question_id)
    REFERENCES session_questions (session_id, question_id) ON DELETE CASCADE
);

-- Indexes (the UNIQUE constraints already index session_id lookups on the two tables above)
CREATE INDEX idx_sessions_candidate ON interview_sessions(candidate_id);
CREATE INDEX idx_sessions_status    ON interview_sessions(status);
CREATE INDEX idx_answers_purge      ON session_answers(status) WHERE audio_storage_path IS NOT NULL;
CREATE INDEX idx_questions_pick     ON questions(difficulty) WHERE is_active;