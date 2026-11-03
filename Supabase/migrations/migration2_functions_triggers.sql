-- updated_at
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger
LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END $$;

CREATE TRIGGER trg_candidates_updated BEFORE UPDATE ON candidates
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_answers_updated BEFORE UPDATE ON session_answers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Auto-create candidate row on signup
CREATE OR REPLACE FUNCTION handle_new_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  INSERT INTO public.candidates (id, full_name, email)
  VALUES (NEW.id,
          COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email,'@',1)),
          NEW.email);
  RETURN NEW;
END $$;

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Server-side time-limit enforcement (limit + 3s grace for network/recorder lag)
CREATE OR REPLACE FUNCTION enforce_answer_duration() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_limit INT;
BEGIN
  SELECT time_limit_seconds INTO v_limit FROM public.questions WHERE id = NEW.question_id;
  IF NEW.duration_seconds IS NOT NULL AND NEW.duration_seconds > v_limit + 3 THEN
    RAISE EXCEPTION 'Answer duration % s exceeds the % s limit', NEW.duration_seconds, v_limit;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_enforce_duration BEFORE INSERT OR UPDATE OF duration_seconds ON session_answers
  FOR EACH ROW EXECUTE FUNCTION enforce_answer_duration();

-- Recompute total_score (0-100) and flip session to 'evaluated' when all answers are scored.
-- Score = average of (technical + communication)/2, scaled x10.
CREATE OR REPLACE FUNCTION recompute_session_score() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_total INT; v_scored INT; v_avg NUMERIC;
BEGIN
  SELECT COUNT(*) INTO v_total FROM public.session_questions WHERE session_id = NEW.session_id;
  SELECT COUNT(*), AVG((technical_accuracy_score + communication_score) / 2.0) * 10
    INTO v_scored, v_avg
    FROM public.session_answers
   WHERE session_id = NEW.session_id
     AND technical_accuracy_score IS NOT NULL AND communication_score IS NOT NULL;

  UPDATE public.interview_sessions
     SET total_score = ROUND(v_avg, 2),
         status = CASE WHEN v_scored = v_total THEN 'evaluated'::public.interview_status ELSE status END
   WHERE id = NEW.session_id;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_recompute_score
  AFTER INSERT OR UPDATE OF technical_accuracy_score, communication_score ON session_answers
  FOR EACH ROW EXECUTE FUNCTION recompute_session_score();

-- Admin check (set role in the user's app_metadata from the dashboard/service role)
CREATE OR REPLACE FUNCTION is_admin() RETURNS BOOLEAN
LANGUAGE sql STABLE SET search_path = '' AS $$
  SELECT COALESCE((SELECT auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', FALSE)
$$;

-- Candidate-safe question fetch (no rubric columns)
CREATE OR REPLACE FUNCTION get_session_questions(p_session_id UUID)
RETURNS TABLE (
    question_id UUID,
    "position" INTEGER,
    question_text TEXT,
    difficulty public.question_difficulty,
    time_limit_seconds INTEGER
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT q.id, sq.position, q.question_text, q.difficulty, q.time_limit_seconds
    FROM public.session_questions sq
    JOIN public.questions q ON q.id = sq.question_id
    JOIN public.interview_sessions s ON s.id = sq.session_id
   WHERE sq.session_id = p_session_id
     AND s.candidate_id = (SELECT auth.uid())
     AND s.status = 'in_progress'
   ORDER BY sq.position
$$;

-- Lifecycle RPCs (candidates can't update sessions directly)
CREATE OR REPLACE FUNCTION start_interview(p_session_id UUID) RETURNS VOID
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE public.interview_sessions
     SET status = 'in_progress', started_at = NOW()
   WHERE id = p_session_id AND candidate_id = (SELECT auth.uid()) AND status = 'scheduled'
$$;

CREATE OR REPLACE FUNCTION complete_interview(p_session_id UUID) RETURNS VOID
LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  UPDATE public.interview_sessions
     SET status = 'completed', completed_at = NOW()
   WHERE id = p_session_id AND candidate_id = (SELECT auth.uid()) AND status = 'in_progress'
$$;

REVOKE EXECUTE ON FUNCTION get_session_questions, start_interview, complete_interview FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION get_session_questions, start_interview, complete_interview TO authenticated;