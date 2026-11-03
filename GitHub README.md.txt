AI-Powered Dynamic Interview Assistant
An end-to-end, zero-cost automated technical interviewing platform. The system dynamically assigns timed questions, automatically stops video/audio recording when deadlines are reached, extracts speech tracks client-side, transcribes candidate responses, and generates multi-criteria feedback using the Gemini API.
________________


Key Features
* Adaptive Time Enforcers:
   * Quick-response check: 20–30 second strict ultimatum limit for one-line/direct definitions.
   * Deep-dive questions: 60–120 second limit for complex architectural or algorithmic answers.
   * Recording automatically terminates when the timer expires to conserve bandwidth and storage.
* Client-Side Demuxing: Uses browser-level audio isolation (MediaRecorder / @ffmpeg/ffmpeg) to strip out oversized video files before upload.
* 100% Free-Tier Native:
   * Database & Auth: Supabase (PostgreSQL with RLS).
   * Evaluation Model: Google Gemini API (Flash tier for low-latency JSON reasoning).
   * Hosting: Vercel / Netlify.
* Auto-Pruning Storage Lifecycle: Once transcripts are generated and scored, temporary audio files are purged from Supabase Storage to maintain usage well within the free 1 GB allocation.
________________


System Architecture
Candidate Browser
 ├── 1. Fetch Question & Difficulty Time Limit
 ├── 2. Record Video/Audio via MediaStream API
 ├── 3. Enforce Auto-Pause at Limit (e.g., 30s)
 └── 4. Demux & Extract 16kHz WAV Audio
          │
          ▼
   Supabase Storage (Transient Bucket)
          │
          ▼
   Processing Layer (Next.js / Node.js / Supabase Edge Functions)
    ├── Speech-to-Text Transcription
    └── Google Gemini 1.5 API (Rubric Evaluation)
          │
          ▼
   Supabase PostgreSQL (`session_answers`)
          │
          ▼
   [Delete Audio from Storage Bucket]

________________
Tech Stack
* Frontend: React / Next.js, Tailwind CSS, Lucide Icons
* Database & Backend: Supabase (PostgreSQL, Storage, Edge Functions, Row Level Security)
* AI & Analysis: Google Gemini API (gemini-1.5-flash), Speech Recognition API / Whisper
* Media Handling: Web Audio API, HTML5 MediaRecorder, WebAssembly FFmpeg (@ffmpeg/ffmpeg)
* Development Tooling: Visual Studio Code, DBeaver / Supabase Studio
________________


Database Schema Overview
The database is built on PostgreSQL with foreign key constraints, custom ENUMs, and automated timestamps:
* candidates: Stores candidate identity and credentials.
* interview_sessions: Tracks interview lifecycle, aggregate performance scores, and metadata.
* questions: Holds interview question bank, assigned difficulty levels, and exact time boundaries (time_limit_seconds).
* session_answers: Stores transcripts, extracted audio references, granular scores (technical accuracy, communication), and LLM feedback.
To review the complete SQL migrations, see system_architecture.md.
________________


Getting Started
1. Prerequisites
* Node.js (v18.x or later)
* Free account on Supabase
* Free API Key from Google AI Studio (Gemini)
2. Environment Variables
Create a .env.local file in the root directory:
```env
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-supabase-anon-key
SUPABASE_SERVICE_ROLE_KEY=your-supabase-service-role-key
GEMINI_API_KEY=your-google-gemini-api-key
```


3. Database Setup
1. Open the SQL Editor in your Supabase Dashboard.
2. Run the SQL schema script provided in system_architecture.md.
3. Create a public/authenticated storage bucket named interview-audio.
4. Installation & Local Development
# Clone the repository
git clone https://github.com/your-username/ai-interview-system.git
cd ai-interview-system


# Install dependencies
npm install


# Run the development server
npm run dev
Open http://localhost:3000 with your browser to view the application.
________________


License
MIT License. Free to use and modify for personal or commercial projects.