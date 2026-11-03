CREATE TYPE proficiency_level  AS ENUM ('beginner','intermediate','advanced');
CREATE TYPE experience_type    AS ENUM ('internship','full_time','part_time','freelance',
                                        'research_internship','industrial_training','open_source','volunteer');
CREATE TYPE project_status     AS ENUM ('planned','in_progress','completed','deployed','abandoned');
CREATE TYPE publication_status AS ENUM ('published','under_review','patent_filed','patent_granted');
CREATE TYPE interview_type     AS ENUM ('technical','hr','behavioral','coding','mixed');
CREATE TYPE interview_level    AS ENUM ('easy','medium','hard');
CREATE TYPE interview_mode     AS ENUM ('voice','video','text');
CREATE TYPE interview_style    AS ENUM ('conversational','formal','stress');
CREATE TYPE question_language  AS ENUM ('english','hindi','hinglish');
CREATE TYPE question_source    AS ENUM ('bank','ai_generated');
CREATE TYPE question_category  AS ENUM ('technical','project','dsa','system_design','hr',
                                        'behavioral','job_specific','coding');
CREATE TYPE consent_type       AS ENUM ('profile_processing','resume_parsing',
                                        'audio_video_processing','ai_analysis');

-- 1. Personal information
CREATE TABLE candidate_profiles (
  candidate_id       UUID PRIMARY KEY REFERENCES candidates(id) ON DELETE CASCADE,
  photo_path         TEXT,
  father_name        VARCHAR(100),                       -- optional
  date_of_birth      DATE CHECK (date_of_birth < CURRENT_DATE),
  gender             VARCHAR(30),                        -- optional
  mobile             VARCHAR(20),
  alt_mobile         VARCHAR(20),
  city VARCHAR(80), state VARCHAR(80), country VARCHAR(80),
  address            TEXT,                               -- optional
  nationality        VARCHAR(60),                        -- optional
  linkedin_url TEXT, github_url TEXT, portfolio_url TEXT, website_url TEXT,
  research_interests TEXT[] NOT NULL DEFAULT '{}',
  wizard_step        INT NOT NULL DEFAULT 1 CHECK (wizard_step BETWEEN 1 AND 9),
  profile_completed  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (COALESCE(linkedin_url,'https://') ~* '^https?://' AND COALESCE(github_url,'https://') ~* '^https?://'
     AND COALESCE(portfolio_url,'https://') ~* '^https?://' AND COALESCE(website_url,'https://') ~* '^https?://')
);

-- 2. Education: one row per qualification (10th, 12th, diploma, bachelors, ...)
CREATE TABLE education (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  level        TEXT NOT NULL CHECK (level IN ('10th','12th','diploma','bachelors','masters','phd','other')),
  status       TEXT NOT NULL DEFAULT 'completed' CHECK (status IN ('completed','pursuing')),
  degree_name  VARCHAR(120),
  specialization VARCHAR(120),
  major_minor  VARCHAR(120),
  institution  VARCHAR(200),                 -- college / university / board
  location     VARCHAR(120),
  enrollment_number VARCHAR(50),             -- optional
  admission_year INT CHECK (admission_year BETWEEN 1980 AND 2100),
  passing_year   INT CHECK (passing_year   BETWEEN 1980 AND 2100),
  current_year_semester VARCHAR(20),
  grade_type   TEXT CHECK (grade_type IN ('cgpa','percentage')),
  grade_value  NUMERIC(5,2),
  backlogs     INT CHECK (backlogs >= 0),
  coursework   TEXT[] NOT NULL DEFAULT '{}',
  details      TEXT,                         -- diploma details, academic notes
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (grade_value IS NULL OR (grade_type='cgpa' AND grade_value BETWEEN 0 AND 10)
                             OR (grade_type='percentage' AND grade_value BETWEEN 0 AND 100)),
  CHECK (passing_year IS NULL OR admission_year IS NULL OR passing_year >= admission_year)
);

-- 3-9 + soft skills: one catalog, one candidate table
CREATE TABLE skill_categories (
  code TEXT PRIMARY KEY, label TEXT NOT NULL, sort_order INT NOT NULL DEFAULT 0
);

CREATE TABLE skills (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category    TEXT NOT NULL REFERENCES skill_categories(code),
  name        VARCHAR(100) NOT NULL,
  is_approved BOOLEAN NOT NULL DEFAULT TRUE,         -- custom skills start unapproved
  created_by  UUID REFERENCES candidates(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_skills_cat_name ON skills (category, LOWER(name));

CREATE TABLE candidate_skills (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  skill_id     UUID NOT NULL REFERENCES skills(id),
  proficiency  proficiency_level,
  years_experience NUMERIC(4,1) CHECK (years_experience BETWEEN 0 AND 60),
  last_used    DATE,
  experience_context TEXT[] NOT NULL DEFAULT '{}'
               CHECK (experience_context <@ ARRAY['academic','personal','professional']),
  project_count INT CHECK (project_count >= 0),
  self_score   INT CHECK (self_score BETWEEN 1 AND 10),   -- self-assessment / confidence
  problems_solved INT CHECK (problems_solved >= 0),       -- DSA topics
  preferred_language VARCHAR(40),                         -- DSA topics
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (candidate_id, skill_id)
);

-- 10. Projects
CREATE TABLE projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  title VARCHAR(150) NOT NULL,
  category VARCHAR(60),
  description TEXT, problem_statement TEXT,
  start_date DATE, end_date DATE,
  status project_status,
  is_team_project BOOLEAN, team_size INT CHECK (team_size >= 1),
  role VARCHAR(100), individual_contribution TEXT, key_technical_contribution TEXT,
  major_challenges TEXT, solutions_implemented TEXT, key_learnings TEXT,
  would_improve TEXT, achievement TEXT,
  deployment_platform VARCHAR(60), is_deployed BOOLEAN, user_count INT CHECK (user_count >= 0),
  is_hackathon BOOLEAN NOT NULL DEFAULT FALSE, is_academic BOOLEAN NOT NULL DEFAULT FALSE,
  github_url TEXT, live_url TEXT, demo_video_url TEXT,
  documentation_path TEXT,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);
CREATE TABLE project_skills (
  project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
  skill_id   UUID REFERENCES skills(id),
  PRIMARY KEY (project_id, skill_id)
);

-- 11. Internships and work experience
CREATE TABLE work_experience (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  kind experience_type NOT NULL,
  company_name VARCHAR(150) NOT NULL, job_title VARCHAR(120),
  location VARCHAR(120),
  start_date DATE, end_date DATE, is_current BOOLEAN NOT NULL DEFAULT FALSE,
  responsibilities TEXT, major_contributions TEXT, achievements TEXT,
  certificate_path TEXT, experience_letter_path TEXT, company_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date),
  CHECK (NOT (is_current AND end_date IS NOT NULL))
);
CREATE TABLE experience_skills (
  experience_id UUID REFERENCES work_experience(id) ON DELETE CASCADE,
  skill_id      UUID REFERENCES skills(id),
  PRIMARY KEY (experience_id, skill_id)
);

-- 12. Certifications
CREATE TABLE certifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  name VARCHAR(200) NOT NULL, issuing_organization VARCHAR(150),
  category TEXT CHECK (category IN ('programming','web_development','data_science','artificial_intelligence',
    'machine_learning','cloud_computing','cybersecurity','database_management','devops','networking',
    'project_management','software_testing','ui_ux_design')),
  level proficiency_level,
  issue_date DATE, expiration_date DATE,
  credential_id VARCHAR(120), verification_url TEXT, certificate_path TEXT,
  course_duration_hours NUMERIC(6,1) CHECK (course_duration_hours >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (expiration_date IS NULL OR issue_date IS NULL OR expiration_date >= issue_date)
);
CREATE TABLE certification_skills (
  certification_id UUID REFERENCES certifications(id) ON DELETE CASCADE,
  skill_id         UUID REFERENCES skills(id),
  PRIMARY KEY (certification_id, skill_id)
);

-- 13. Hackathons and other achievements
CREATE TABLE hackathon_participations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  project_id UUID REFERENCES projects(id) ON DELETE SET NULL,
  name VARCHAR(200) NOT NULL, organizer VARCHAR(150),
  participation_date DATE, category VARCHAR(80),
  team_name VARCHAR(100), team_size INT CHECK (team_size >= 1), role VARCHAR(100),
  problem_statement TEXT, solution_developed TEXT,
  position_secured VARCHAR(80), prize VARCHAR(150),
  certificate_path TEXT, event_url TEXT, repo_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE hackathon_skills (
  hackathon_id UUID REFERENCES hackathon_participations(id) ON DELETE CASCADE,
  skill_id     UUID REFERENCES skills(id),
  PRIMARY KEY (hackathon_id, skill_id)
);

CREATE TABLE achievements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('academic_award','scholarship','coding_ranking','competition',
        'paper_presentation','google_dev_event','innovation_challenge','college_award','national_level','other')),
  title VARCHAR(200) NOT NULL, issuer VARCHAR(150),
  level TEXT CHECK (level IN ('college','state','national','international')),
  achievement_date DATE, description TEXT, url TEXT, certificate_path TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 14. Extracurriculars, leadership
CREATE TABLE activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  kind TEXT NOT NULL CHECK (kind IN ('extracurricular','leadership')),
  category VARCHAR(60),                       -- Sports, Public Speaking, Team Leader, ...
  name VARCHAR(150) NOT NULL, organization VARCHAR(150), position VARCHAR(100),
  start_date DATE, end_date DATE,
  responsibilities TEXT, achievements TEXT, certificate_path TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (end_date IS NULL OR start_date IS NULL OR end_date >= start_date)
);

-- 16. Coding profiles
CREATE TABLE coding_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  platform TEXT NOT NULL CHECK (platform IN ('leetcode','codechef','codeforces','hackerrank',
                                'geeksforgeeks','hackerearth','atcoder','github')),
  username VARCHAR(100), profile_url TEXT,
  rating INT, rank_label VARCHAR(60), stars INT CHECK (stars BETWEEN 0 AND 7),
  problems_solved INT CHECK (problems_solved >= 0),
  badges TEXT[] NOT NULL DEFAULT '{}',
  extra JSONB NOT NULL DEFAULT '{}',          -- repos, contributions, scores, achievements
  fetched_at TIMESTAMPTZ,                     -- when public stats were last pulled
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (candidate_id, platform)
);
CREATE TABLE candidate_coding_summary (
  candidate_id UUID PRIMARY KEY REFERENCES candidates(id) ON DELETE CASCADE,
  total_solved INT, easy_solved INT, medium_solved INT, hard_solved INT,
  highest_contest_rating INT, daily_streak INT,
  preferred_dsa_topics TEXT[] NOT NULL DEFAULT '{}',
  cp_experience TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 17. Research and publications (also patents)
CREATE TABLE research_publications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  title VARCHAR(300) NOT NULL, venue VARCHAR(200),
  publication_date DATE, doi_or_url TEXT,
  author_position INT CHECK (author_position >= 1),
  domain VARCHAR(100), methodology TEXT,
  status publication_status, is_patent BOOLEAN NOT NULL DEFAULT FALSE, patent_details TEXT,
  technologies TEXT[] NOT NULL DEFAULT '{}',
  paper_path TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 18. Languages
CREATE TABLE candidate_languages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  language VARCHAR(50) NOT NULL,
  proficiency TEXT CHECK (proficiency IN ('basic','conversational','fluent','native')),
  is_native BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (candidate_id, language)
);

-- 20. Self-assessment, goals, learning, communication
CREATE TABLE candidate_self_assessment (
  candidate_id UUID PRIMARY KEY REFERENCES candidates(id) ON DELETE CASCADE,
  favourite_subjects TEXT[] NOT NULL DEFAULT '{}',
  strongest_subjects TEXT[] NOT NULL DEFAULT '{}',
  weakest_subjects   TEXT[] NOT NULL DEFAULT '{}',
  strongest_skills   TEXT[] NOT NULL DEFAULT '{}',
  weakest_skills     TEXT[] NOT NULL DEFAULT '{}',
  currently_learning TEXT[] NOT NULL DEFAULT '{}',
  technical_interests TEXT[] NOT NULL DEFAULT '{}',
  learning_preferences TEXT[] NOT NULL DEFAULT '{}',
  written_comm_level TEXT CHECK (written_comm_level IN ('basic','good','excellent')),
  verbal_comm_level  TEXT CHECK (verbal_comm_level  IN ('basic','good','excellent')),
  presentation_skill_score INT CHECK (presentation_skill_score BETWEEN 1 AND 10),
  public_speaking_confidence INT CHECK (public_speaking_confidence BETWEEN 1 AND 10),
  work_preference TEXT CHECK (work_preference IN ('individual','team','both')),
  problem_solving_approach TEXT,
  short_term_goals TEXT, long_term_goals TEXT,
  availability TEXT[] NOT NULL DEFAULT '{}',   -- internships, jobs, interviews
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 15. Career preferences + job descriptions
CREATE TABLE job_descriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  title VARCHAR(150), company VARCHAR(150),
  jd_text TEXT, file_path TEXT,
  parsed JSONB,                               -- required skills, responsibilities (AI extracted)
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (jd_text IS NOT NULL OR file_path IS NOT NULL)
);

CREATE TABLE career_preferences (
  candidate_id UUID PRIMARY KEY REFERENCES candidates(id) ON DELETE CASCADE,
  target_roles TEXT[] NOT NULL DEFAULT '{}',          -- multiple allowed
  preferred_industries TEXT[] NOT NULL DEFAULT '{}',
  preferred_company VARCHAR(150),
  job_types TEXT[] NOT NULL DEFAULT '{}' CHECK (job_types <@ ARRAY['full_time','internship','part_time']),
  experience_level TEXT CHECK (experience_level IN ('fresher','experienced')),
  preferred_locations TEXT[] NOT NULL DEFAULT '{}',
  work_mode TEXT CHECK (work_mode IN ('remote','hybrid','on_site')),
  expected_ctc NUMERIC(12,2),                          -- optional
  notice_period_days INT CHECK (notice_period_days >= 0),  -- optional
  target_interview_date DATE,
  career_objective TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 19. Interview preferences (defaults; snapshotted onto each session)
CREATE TABLE interview_preferences (
  candidate_id UUID PRIMARY KEY REFERENCES candidates(id) ON DELETE CASCADE,
  interview_type interview_type NOT NULL DEFAULT 'mixed',
  difficulty interview_level NOT NULL DEFAULT 'medium',
  duration_minutes INT NOT NULL DEFAULT 30 CHECK (duration_minutes IN (15,30,45,60)),
  question_language question_language NOT NULL DEFAULT 'english',
  style interview_style NOT NULL DEFAULT 'conversational',
  mode interview_mode NOT NULL DEFAULT 'voice',
  coding_round BOOLEAN NOT NULL DEFAULT FALSE,
  dsa_round BOOLEAN NOT NULL DEFAULT FALSE,
  project_questions BOOLEAN NOT NULL DEFAULT TRUE,
  resume_questions BOOLEAN NOT NULL DEFAULT TRUE,
  hr_questions BOOLEAN NOT NULL DEFAULT TRUE,
  system_design_questions BOOLEAN NOT NULL DEFAULT FALSE,
  follow_up_questions BOOLEAN NOT NULL DEFAULT TRUE,
  feedback_detail TEXT NOT NULL DEFAULT 'detailed' CHECK (feedback_detail IN ('detailed','short')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Resume + AI analysis + consent
CREATE TABLE resume_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  file_path TEXT NOT NULL,
  file_type TEXT NOT NULL CHECK (file_type IN ('pdf','docx')),
  is_primary BOOLEAN NOT NULL DEFAULT TRUE,
  parse_status TEXT NOT NULL DEFAULT 'pending' CHECK (parse_status IN ('pending','parsed','failed')),
  parsed_json JSONB,                          -- structured extraction; avoid storing full raw text
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE UNIQUE INDEX uq_one_primary_resume ON resume_documents(candidate_id) WHERE is_primary;

CREATE TABLE profile_analyses (               -- output of the AI Profile Analyzer (service role writes)
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  job_description_id UUID REFERENCES job_descriptions(id) ON DELETE SET NULL,
  summary TEXT,
  extracted_skills JSONB, skill_gaps JSONB, strengths JSONB, suggested_topics JSONB,
  model VARCHAR(60),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE consents (
  candidate_id UUID NOT NULL REFERENCES candidates(id) ON DELETE CASCADE,
  consent_type consent_type NOT NULL,
  granted BOOLEAN NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (candidate_id, consent_type)
);