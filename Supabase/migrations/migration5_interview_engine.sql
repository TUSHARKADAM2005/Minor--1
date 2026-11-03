-- Sessions remember the configuration they were created with
ALTER TABLE interview_sessions
  ADD COLUMN interview_type      interview_type     NOT NULL DEFAULT 'mixed',
  ADD COLUMN overall_difficulty  interview_level    NOT NULL DEFAULT 'medium',
  ADD COLUMN mode                interview_mode     NOT NULL DEFAULT 'voice',
  ADD COLUMN style                interview_style    NOT NULL DEFAULT 'conversational',
  ADD COLUMN question_language   question_language  NOT NULL DEFAULT 'english',
  ADD COLUMN duration_minutes    INT NOT NULL DEFAULT 30 CHECK (duration_minutes IN (15,30,45,60)),
  ADD COLUMN job_description_id  UUID REFERENCES job_descriptions(id) ON DELETE SET NULL,
  ADD COLUMN config              JSONB NOT NULL DEFAULT '{}';

-- Questions can now be AI-generated for one candidate from their profile
ALTER TABLE questions
  ADD COLUMN source question_source NOT NULL DEFAULT 'bank',
  ADD COLUMN category question_category NOT NULL DEFAULT 'technical',
  ADD COLUMN generated_for_candidate UUID REFERENCES candidates(id) ON DELETE CASCADE,
  ADD COLUMN related_skill_id UUID REFERENCES skills(id) ON DELETE SET NULL,
  ADD COLUMN related_project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  ADD COLUMN generation_meta JSONB,
  ADD CONSTRAINT chk_generated_owner
      CHECK ((source = 'ai_generated') = (generated_for_candidate IS NOT NULL));

-- Update foreign key
ALTER TABLE session_questions
  DROP CONSTRAINT session_questions_question_id_fkey;

ALTER TABLE session_questions
  ADD CONSTRAINT session_questions_question_id_fkey
  FOREIGN KEY (question_id) REFERENCES questions(id);

-- Adaptive follow-ups
ALTER TABLE session_questions
  ADD COLUMN parent_id UUID REFERENCES session_questions(id) ON DELETE CASCADE;

-- Indexes
CREATE INDEX idx_questions_candidate
ON questions(generated_for_candidate)
WHERE generated_for_candidate IS NOT NULL;

CREATE INDEX idx_questions_category
ON questions(category, difficulty)
WHERE is_active;

-- Candidate-safe fetch
DROP FUNCTION IF EXISTS get_session_questions(UUID);

CREATE FUNCTION get_session_questions(p_session_id UUID)
RETURNS TABLE (
    question_id UUID,
    "position" INT,
    question_text TEXT,
    category public.question_category,
    difficulty public.question_difficulty,
    time_limit_seconds INT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
      q.id,
      sq.position,
      q.question_text,
      q.category,
      q.difficulty,
      q.time_limit_seconds
  FROM public.session_questions sq
  JOIN public.questions q ON q.id = sq.question_id
  JOIN public.interview_sessions s ON s.id = sq.session_id
  WHERE sq.session_id = p_session_id
    AND s.candidate_id = (SELECT auth.uid())
    AND s.status = 'in_progress'
  ORDER BY sq.position;
$$;

REVOKE EXECUTE ON FUNCTION get_session_questions(UUID)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION get_session_questions(UUID)
TO authenticated;

-- Starting an interview requires audio/video consent
CREATE OR REPLACE FUNCTION start_interview(p_session_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
      SELECT 1
      FROM public.consents
      WHERE candidate_id = (SELECT auth.uid())
        AND consent_type = 'audio_video_processing'
        AND granted
  ) THEN
    RAISE EXCEPTION 'Audio/video processing consent is required before starting';
  END IF;

  UPDATE public.interview_sessions
  SET status = 'in_progress',
      started_at = NOW()
  WHERE id = p_session_id
    AND candidate_id = (SELECT auth.uid())
    AND status = 'scheduled';
END;
$$;

-- Create profile row automatically at signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.candidates (id, full_name, email)
  VALUES (
      NEW.id,
      COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email,'@',1)),
      NEW.email
  );

  INSERT INTO public.candidate_profiles (candidate_id)
  VALUES (NEW.id);

  RETURN NEW;
END;
$$;