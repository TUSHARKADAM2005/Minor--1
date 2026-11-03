ALTER TABLE candidates         ENABLE ROW LEVEL SECURITY;
ALTER TABLE questions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE interview_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_questions  ENABLE ROW LEVEL SECURITY;
ALTER TABLE session_answers    ENABLE ROW LEVEL SECURITY;

-- Lock down table privileges first (Supabase grants broad access by default)
REVOKE ALL ON candidates, questions, interview_sessions, session_questions, session_answers FROM anon, authenticated;
GRANT SELECT ON candidates, interview_sessions, session_questions, session_answers, questions TO authenticated;
GRANT UPDATE (full_name) ON candidates TO authenticated;
GRANT INSERT (session_id, question_id, audio_storage_path, duration_seconds) ON session_answers TO authenticated;

-- candidates
CREATE POLICY cand_select ON candidates FOR SELECT TO authenticated
  USING (id = (SELECT auth.uid()) OR (SELECT is_admin()));
CREATE POLICY cand_update ON candidates FOR UPDATE TO authenticated
  USING (id = (SELECT auth.uid())) WITH CHECK (id = (SELECT auth.uid()));

-- questions: admin read only (candidates use get_session_questions)
CREATE POLICY q_admin_select ON questions FOR SELECT TO authenticated USING ((SELECT is_admin()));

-- sessions
CREATE POLICY sess_select ON interview_sessions FOR SELECT TO authenticated
  USING (candidate_id = (SELECT auth.uid()) OR (SELECT is_admin()));

-- session_questions
CREATE POLICY sq_select ON session_questions FOR SELECT TO authenticated
  USING ((SELECT is_admin()) OR EXISTS (
    SELECT 1 FROM interview_sessions s
     WHERE s.id = session_id AND s.candidate_id = (SELECT auth.uid())));

-- answers: read own; insert only into own in-progress session
CREATE POLICY ans_select ON session_answers FOR SELECT TO authenticated
  USING ((SELECT is_admin()) OR EXISTS (
    SELECT 1 FROM interview_sessions s
     WHERE s.id = session_id AND s.candidate_id = (SELECT auth.uid())));
CREATE POLICY ans_insert ON session_answers FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM interview_sessions s
     WHERE s.id = session_id AND s.candidate_id = (SELECT auth.uid()) AND s.status = 'in_progress'));

-- Private audio bucket, 1 MB cap, WAV only
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('candidate-audio','candidate-audio', FALSE, 1048576,
        ARRAY['audio/wav','audio/x-wav','audio/wave'])
ON CONFLICT (id) DO NOTHING;

-- Candidates may upload only into their own folder: {auth.uid()}/{session_id}/{question_id}.wav
CREATE POLICY audio_upload_own ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'candidate-audio'
              AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);
-- No select/update/delete policies for candidates. Your Edge Function uses the service role.