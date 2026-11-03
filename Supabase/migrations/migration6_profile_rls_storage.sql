-- Owner-only tables: lock down, RLS, owner CRUD, admin read, FK index, updated_at trigger
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'candidate_profiles','education','candidate_skills','projects','work_experience','certifications',
    'hackathon_participations','achievements','activities','coding_profiles','candidate_coding_summary',
    'research_publications','candidate_languages','candidate_self_assessment','job_descriptions',
    'career_preferences','interview_preferences','resume_documents','consents'] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('REVOKE ALL ON %I FROM anon, authenticated', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON %I TO authenticated', t);
    EXECUTE format($p$CREATE POLICY %I ON %I FOR ALL TO authenticated
      USING (candidate_id = (SELECT auth.uid())) WITH CHECK (candidate_id = (SELECT auth.uid()))$p$, t||'_owner', t);
    EXECUTE format($p$CREATE POLICY %I ON %I FOR SELECT TO authenticated
      USING ((SELECT is_admin()))$p$, t||'_admin_read', t);
    IF t <> 'candidate_profiles' THEN
      EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I (candidate_id)', 'idx_'||t||'_cand', t);
    END IF;
    IF t <> 'candidate_languages' THEN  -- tables that have updated_at
      EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
                     'trg_'||t||'_updated', t);
    END IF;
  END LOOP;
END $$;

-- Junction tables: ownership is checked through the parent row
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT * FROM (VALUES
      ('project_skills','projects','project_id'),
      ('experience_skills','work_experience','experience_id'),
      ('certification_skills','certifications','certification_id'),
      ('hackathon_skills','hackathon_participations','hackathon_id')) AS v(j,p,c) LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', r.j);
    EXECUTE format('REVOKE ALL ON %I FROM anon, authenticated', r.j);
    EXECUTE format('GRANT SELECT, INSERT, DELETE ON %I TO authenticated', r.j);
    EXECUTE format($p$CREATE POLICY %I ON %I FOR ALL TO authenticated
      USING (EXISTS (SELECT 1 FROM %I x WHERE x.id = %I AND x.candidate_id = (SELECT auth.uid())))
      WITH CHECK (EXISTS (SELECT 1 FROM %I x WHERE x.id = %I AND x.candidate_id = (SELECT auth.uid())))$p$,
      r.j||'_owner', r.j, r.p, r.c, r.p, r.c);
    EXECUTE format($p$CREATE POLICY %I ON %I FOR SELECT TO authenticated
      USING ((SELECT is_admin()))$p$, r.j||'_admin_read', r.j);
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON %I (skill_id)', 'idx_'||r.j||'_skill', r.j);
  END LOOP;
END $$;

-- Skill catalog: everyone reads approved skills; candidates may add unapproved custom ones
ALTER TABLE skill_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE skills           ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON skill_categories, skills FROM anon, authenticated;
GRANT SELECT ON skill_categories, skills TO authenticated;
GRANT INSERT (category, name, created_by, is_approved) ON skills TO authenticated;
CREATE POLICY cat_read    ON skill_categories FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY skills_read ON skills FOR SELECT TO authenticated
  USING (is_approved OR created_by = (SELECT auth.uid()) OR (SELECT is_admin()));
CREATE POLICY skills_add  ON skills FOR INSERT TO authenticated
  WITH CHECK (created_by = (SELECT auth.uid()) AND is_approved = FALSE);

-- Interview-engine outputs: candidates may read, only the service role writes
ALTER TABLE profile_analyses ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON profile_analyses FROM anon, authenticated;
GRANT SELECT ON profile_analyses TO authenticated;
CREATE POLICY pa_read ON profile_analyses FOR SELECT TO authenticated
  USING (candidate_id = (SELECT auth.uid()) OR (SELECT is_admin()));
CREATE INDEX idx_profile_analyses_cand ON profile_analyses(candidate_id, created_at DESC);

-- Private buckets for profile files; each candidate gets {auth.uid()}/... only
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
 ('profile-photos','profile-photos', FALSE, 2097152, ARRAY['image/jpeg','image/png','image/webp']),
 ('candidate-documents','candidate-documents', FALSE, 10485760,
   ARRAY['application/pdf','application/vnd.openxmlformats-officedocument.wordprocessingml.document',
         'image/jpeg','image/png'])
ON CONFLICT (id) DO NOTHING;

CREATE POLICY profile_files_own ON storage.objects FOR ALL TO authenticated
  USING (bucket_id IN ('profile-photos','candidate-documents')
         AND (storage.foldername(name))[1] = (SELECT auth.uid())::text)
  WITH CHECK (bucket_id IN ('profile-photos','candidate-documents')
         AND (storage.foldername(name))[1] = (SELECT auth.uid())::text);

-- Wizard progress: one boolean per step plus a percentage (RLS applies to the caller)
CREATE VIEW v_profile_completion WITH (security_invoker = true) AS
SELECT *, ROUND(100.0 * (personal::int + education::int + skills::int + experience_projects::int
        + certs_achievements::int + extracurricular::int + career::int + interview_prefs::int + resume::int) / 9) AS percent
FROM (
  SELECT p.candidate_id,
    (p.mobile IS NOT NULL AND p.city IS NOT NULL AND p.country IS NOT NULL)                AS personal,
    EXISTS (SELECT 1 FROM education e WHERE e.candidate_id = p.candidate_id)               AS education,
    EXISTS (SELECT 1 FROM candidate_skills s WHERE s.candidate_id = p.candidate_id)        AS skills,
    (EXISTS (SELECT 1 FROM projects x WHERE x.candidate_id = p.candidate_id)
     OR EXISTS (SELECT 1 FROM work_experience w WHERE w.candidate_id = p.candidate_id))    AS experience_projects,
    (EXISTS (SELECT 1 FROM certifications c WHERE c.candidate_id = p.candidate_id)
     OR EXISTS (SELECT 1 FROM hackathon_participations h WHERE h.candidate_id = p.candidate_id)
     OR EXISTS (SELECT 1 FROM achievements a WHERE a.candidate_id = p.candidate_id))       AS certs_achievements,
    (EXISTS (SELECT 1 FROM activities ac WHERE ac.candidate_id = p.candidate_id)
     OR EXISTS (SELECT 1 FROM candidate_self_assessment sa WHERE sa.candidate_id = p.candidate_id)) AS extracurricular,
    EXISTS (SELECT 1 FROM career_preferences cp WHERE cp.candidate_id = p.candidate_id)    AS career,
    EXISTS (SELECT 1 FROM interview_preferences ip WHERE ip.candidate_id = p.candidate_id) AS interview_prefs,
    EXISTS (SELECT 1 FROM resume_documents r WHERE r.candidate_id = p.candidate_id)        AS resume
  FROM candidate_profiles p
) t;
GRANT SELECT ON v_profile_completion TO authenticated;