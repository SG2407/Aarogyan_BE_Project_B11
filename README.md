# Aarogyan — AI-Powered Personal Health Companion

> A full-stack mobile health application that puts your complete medical history, an intelligent AI doctor, emotional wellness companion, and consultation tracker all in one place.

Aarogyan is built with **Flutter** (frontend) and **Python FastAPI** (backend), backed by **Supabase** for database and storage, **Groq** for LLM inference, and **Qdrant** for a medical knowledge RAG pipeline.

---

## Table of Contents

1. [Features](#features)
2. [Tech Stack](#tech-stack)
3. [Architecture Overview](#architecture-overview)
4. [Project Structure](#project-structure)
5. [API Reference](#api-reference)
6. [Database Schema](#database-schema)
7. [Getting Started](#getting-started)
8. [Environment Variables](#environment-variables)
9. [Deployment](#deployment)
10. [Design System](#design-system)
11. [License](#license)

---

## Features

### Health Profile
Maintain a comprehensive medical profile with 9 structured sections:
- Personal information (DOB, sex, height, weight, blood group, city)
- Existing medical conditions with severity and diagnosis year
- Allergies (type, reaction, severity)
- Current medications and supplements (dosage, frequency, route)
- Past medical and surgical history
- Family medical history
- Lifestyle data (activity level, diet, sleep, smoking/alcohol)
- Mental health information
- Emergency contact details

### Consultation Tracker
Organise all your doctor interactions:
- Group multiple doctor visits under named consultations (e.g. "Diabetes Management 2025")
- Log individual sessions with visit date, symptoms, diagnosis, medications, and doctor notes
- Attach prescription images or lab report PDFs to any session — text is automatically OCR-extracted
- Download a fully formatted **PDF report** of any consultation at any time

### AI Medical Assistant
A personalised LLM-powered health chatbot:
- Chat history preserved across sessions in named conversations
- Uses your full health profile as context in every response
- **RAG pipeline**: queries a Qdrant vector database of pre-ingested medical knowledge for evidence-grounded answers
- LLM router distinguishes "general" queries (direct answer) from "detailed" queries (RAG + profile context)
- Supports language preference (English, Hindi, Marathi)
- Powered by **Groq** (`llama-3.3-70b-versatile`)

### Document Summariser
Instantly understand any medical document:
- Upload a PDF, JPG, or PNG prescription or lab report
- **EasyOCR + PyMuPDF** extracts raw text (handles handwritten prescriptions)
- AI returns a structured summary: document type, plain-language explanation, key findings, and recommended action items

### Emotional Buddy — Orbz
A voice-first emotional wellness companion:
- Hold a voice conversation: your audio is transcribed via **OpenAI Whisper STT**, then Orbz responds with an empathetic reply synthesised with **OpenAI TTS**
- Select from 12 voice personas (6 female, 6 male) with preview samples
- Supports text conversation as well as voice
- Dual emotion detection: ML text model + Wav2Vec2 audio emotion model fused together
- Mood score (1–10) logged for every interaction

### Mental Health Dashboard
Visualise emotional wellness over time:
- Daily, weekly, and monthly average mood score charts
- Emotion distribution breakdown (happy / sad / angry / neutral)
- Session history with conversation previews
- Configurable time window (7 / 30 / 90 days / all time)

---

## Tech Stack

### Backend

| Category | Technology | Purpose |
|----------|-----------|---------|
| Language | Python 3.13 | Core language |
| Web Framework | FastAPI 0.135 | REST API, async request handling, auto OpenAPI docs |
| ASGI Server | Uvicorn + uvloop | High-performance async server |
| Database | Supabase (PostgreSQL) | All structured data storage |
| File Storage | Supabase Storage | Uploaded PDFs and images |
| Authentication | JWT (python-jose) + bcrypt | Stateless token auth, secure password hashing |
| LLM Inference | Groq API (`llama-3.3-70b-versatile`) | Chat, summarisation, buddy, query routing |
| Vector DB | Qdrant Cloud | Semantic search over medical knowledge base |
| Embeddings | `BAAI/bge-small-en-v1.5` | Embeds queries for RAG |
| Reranker | `cross-encoder/ms-marco-MiniLM-L-6-v2` | Reranks top Qdrant results for precision |
| OCR | EasyOCR + PyMuPDF | Extracts text from uploaded documents and handwritten prescriptions |
| Speech-to-Text | OpenAI Whisper API | Transcribes voice audio to text |
| Text-to-Speech | OpenAI TTS API (nova) | Synthesises Orbz's voice responses |
| Emotion Detection | HuggingFace Transformers + Wav2Vec2 | Text and audio emotion classification |
| PDF Generation | fpdf2 | Generates formatted consultation PDF reports |
| Config | pydantic-settings | Typed env-var loading from `.env` |

### Frontend

| Category | Technology | Purpose |
|----------|-----------|---------|
| Language | Dart | Core language |
| Framework | Flutter 3.x | Cross-platform UI (Android + iOS) |
| State Management | Riverpod 2 (code-gen) | App-wide reactive state with `riverpod_generator` |
| HTTP Client | Dio 5 | API requests with automatic JWT auth interceptor |
| Routing | GoRouter 14 | Declarative navigation with auth-guard redirects |
| Secure Storage | flutter_secure_storage | JWT token and user_id encrypted on device |
| Local Preferences | shared_preferences | Light/dark theme persistence |
| Fonts | Google Fonts (DM Sans) | App-wide typography |
| Charts | fl_chart | Mood trend and emotion distribution charts |
| Audio Recording | record + just_audio + audioplayers | Voice capture and playback for Orbz |
| Voice Activity | vad | Voice activity detection |
| PDF / Printing | pdf + printing | PDF export and share |
| Animations | lottie + flutter_animate | UI motion and loading states |
| File Handling | file_picker + image_picker | Document upload flows |
| Code Generation | build_runner, freezed, json_serializable, retrofit_generator | Boilerplate generation |

---

## Architecture Overview

```
┌─────────────────────────────────────────┐
│              Flutter App                │
│  Riverpod state → Dio (JWT interceptor) │
│  GoRouter → auth-guarded screens        │
└──────────────────┬──────────────────────┘
                   │ HTTPS  /api/v1
┌──────────────────▼──────────────────────┐
│           FastAPI Backend               │
│  9 Routers  →  Services layer           │
│  ┌──────────┐  ┌─────────┐  ┌────────┐ │
│  │ JWT Auth │  │  Groq   │  │EasyOCR │ │
│  └────┬─────┘  └────┬────┘  └───┬────┘ │
│       │             │           │      │
│  ┌────▼─────────────▼───────────▼────┐ │
│  │         Supabase (PostgreSQL)     │ │
│  │  users · profiles · consultations │ │
│  │  sessions · conversations ·       │ │
│  │  messages · emotional_sessions    │ │
│  └───────────────────────────────────┘ │
│  ┌──────────────┐  ┌─────────────────┐ │
│  │ Qdrant Cloud │  │Supabase Storage │ │
│  │ (RAG vectors)│  │ (files / PDFs)  │ │
│  └──────────────┘  └─────────────────┘ │
└─────────────────────────────────────────┘
```

**Request flow for AI Medical Assistant chat:**
1. Flutter sends user message with JWT
2. FastAPI extracts `user_id` from JWT → loads health profile from Supabase
3. LLM router classifies query (General / Detailed)
4. For Detailed: embeds query → searches Qdrant → reranks hits → builds RAG context
5. Groq LLM generates response using profile + RAG context + conversation history
6. Response + user message saved to `messages` and `conversations` tables
7. Response returned to Flutter

---

## Project Structure

```
aarogyan_be_project/
│
├── Backend/                              ← Python FastAPI backend
│   ├── main.py                           ← App entry, router registration, CORS, RAG warm-up
│   ├── requirements.txt                  ← All Python dependencies (pinned versions)
│   ├── Dockerfile                        ← Container build for deployment
│   ├── supabase_schema.sql               ← Full PostgreSQL schema (run in Supabase SQL editor)
│   │
│   └── app/
│       ├── config.py                     ← pydantic-settings: loads all env vars from .env
│       ├── database.py                   ← Supabase client singleton (service-role key)
│       ├── auth.py                       ← bcrypt hashing, JWT create/decode, FastAPI Depends
│       │
│       ├── routers/
│       │   ├── auth.py                   ← POST /auth/signup, POST /auth/login
│       │   ├── profile.py                ← GET/PUT /profile/me
│       │   ├── consultations.py          ← CRUD /consultations
│       │   ├── sessions.py               ← CRUD sessions + document upload/delete
│       │   ├── assistant.py              ← Conversation management + /assistant/chat
│       │   ├── documents.py              ← POST /documents/summarise
│       │   ├── buddy.py                  ← Voice + text emotional companion (Orbz)
│       │   ├── mental_health.py          ← GET /mental-health/dashboard
│       │   └── export.py                 ← GET /export/consultation/{id}/pdf
│       │
│       └── services/
│           ├── ai.py                     ← All Groq LLM calls: chat, summarise, buddy, router
│           ├── rag_pipeline.py           ← RAG: embed → Qdrant search → rerank → context string
│           ├── ocr.py                    ← EasyOCR + PyMuPDF text extraction
│           ├── stt.py                    ← OpenAI Whisper STT
│           ├── tts.py                    ← OpenAI TTS (Sarvam fallback)
│           ├── emotion_detection.py      ← Text + audio emotion ML models
│           ├── fusion_engine.py          ← Fuses text and audio emotion probabilities
│           ├── voice_features.py         ← Extracts acoustic voice features for context
│           ├── pdf_export.py             ← fpdf2 formatted consultation PDF
│           ├── consultation_pdf_service.py ← Background PDF rebuild trigger
│           ├── profile_context.py        ← Serialises user profile to plain-text for LLM
│           └── session_analytics.py      ← Per-session mood/emotion aggregation
│
├── lib/                                  ← Flutter frontend (Dart)
│   ├── main.dart                         ← App entry: ProviderScope, MaterialApp, theme
│   │
│   └── src/
│       ├── core/
│       │   ├── network/
│       │   │   ├── dio_client.dart       ← Dio instance, JWT interceptor, base URL
│       │   │   └── token_storage.dart    ← flutter_secure_storage wrapper
│       │   ├── router/
│       │   │   └── app_router.dart       ← GoRouter routes + auth-redirect guard
│       │   └── theme/
│       │       ├── app_theme.dart        ← Material 3 light/dark theme, DM Sans, teal palette
│       │       └── theme_provider.dart   ← Riverpod notifier, persists theme choice
│       │
│       ├── features/
│       │   ├── auth/                     ← Login, signup, splash
│       │   ├── home/                     ← Bottom-nav shell + dashboard
│       │   ├── profile/                  ← Multi-step profile setup + view/edit
│       │   ├── consultation/             ← Consultation list, detail, session detail
│       │   ├── assistant/                ← Conversation list + AI chat screen
│       │   ├── document/                 ← Document upload + summary display
│       │   ├── buddy/                    ← Orbz voice companion UI
│       │   └── mental_health/            ← Mood charts + session history
│       │
│       └── shared/
│           └── widgets/
│               ├── app_button.dart       ← Reusable styled button
│               ├── app_text_field.dart   ← Reusable styled text input
│               └── section_header.dart  ← Reusable section title widget
│
├── android/                              ← Android platform config
├── ios/                                  ← iOS platform config
├── assets/
│   └── images/                           ← App image assets
├── pubspec.yaml                          ← Flutter dependencies
└── analysis_options.yaml                 ← Dart lint rules
```

---

## API Reference

All endpoints are prefixed with `/api/v1`. Protected endpoints require the header:

```
Authorization: Bearer <JWT_TOKEN>
```

### Authentication  `/api/v1/auth`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/auth/signup` | Public | Register a new account. Body: `{email, password, full_name}`. Returns `{token, user_id}` |
| `POST` | `/auth/login` | Public | Login with credentials. Body: `{email, password}`. Returns `{token, user_id}` |

### Profile  `/api/v1/profile`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/profile/me` | Required | Fetch the full health profile for the logged-in user |
| `PUT` | `/profile/me` | Required | Create or update (upsert) any profile fields. All fields are optional |

Profile includes: personal info, existing conditions, allergies, medications, supplements, past medical history, family history, lifestyle, and mental health data.

### Consultations  `/api/v1/consultations`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/consultations/` | Required | List all consultations for the user |
| `POST` | `/consultations/` | Required | Create a consultation. Body: `{name, start_date?, notes?}` |
| `GET` | `/consultations/{id}` | Required | Get a single consultation |
| `PATCH` | `/consultations/{id}` | Required | Update consultation fields |
| `DELETE` | `/consultations/{id}` | Required | Delete a consultation and all its sessions |

### Sessions  `/api/v1/consultations/{consultation_id}/sessions`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/sessions/` | Required | List all sessions (with attached documents) |
| `POST` | `/sessions/` | Required | Create a session. Body: `{visit_date, symptoms?, diagnosis?, medications?, doctor_notes?}` |
| `GET` | `/sessions/{session_id}` | Required | Get a single session with all documents |
| `PATCH` | `/sessions/{session_id}` | Required | Update session fields |
| `DELETE` | `/sessions/{session_id}` | Required | Delete session and its documents |
| `POST` | `/sessions/{session_id}/documents` | Required | Upload a PDF/JPG/PNG. OCR extracted automatically. Stored in Supabase Storage |
| `DELETE` | `/sessions/{session_id}/documents/{doc_id}` | Required | Delete document from DB and Storage |

### Medical Assistant  `/api/v1/assistant`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/assistant/conversations` | Required | List all conversations |
| `POST` | `/assistant/conversations` | Required | Create a new conversation |
| `GET` | `/assistant/conversations/{id}` | Required | Get conversation with full message history |
| `DELETE` | `/assistant/conversations/{id}` | Required | Delete a conversation |
| `POST` | `/assistant/chat` | Required | Send a message. Body: `{message, conversation_id?, preferred_language?}`. Returns AI response |

The `/assistant/chat` endpoint:
1. Loads the user's health profile as context
2. Classifies the query (general vs. detailed via LLM router)
3. For detailed queries: embeds the question, retrieves from Qdrant, reranks results
4. Sends profile + RAG context + history to Groq
5. Persists user message and AI reply to the `messages` table

### Document Summarisation  `/api/v1/documents`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/documents/summarise` | Required | Upload PDF/JPG/PNG (max 1.5 MB). Returns `{ocr_text, summary}` with structured AI analysis |

Summary includes: `document_type`, `explanation`, `key_findings`, `action_items`, `disclaimer`.

### Emotional Buddy (Orbz)  `/api/v1/buddy`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/buddy/voice` | Required | Upload audio → STT → AI response → TTS → returns `{transcript, buddy_text, mood_score, audio_base64}` |
| `POST` | `/buddy/text` | Required | Text message → AI empathetic response. Body: `{text, history?, preferred_language?, session_group_id?}` |
| `GET` | `/buddy/sessions` | Required | List all buddy sessions |
| `GET` | `/buddy/sessions/{id}` | Required | Get single buddy session |
| `GET` | `/buddy/voices` | Required | List available TTS voice catalogue |
| `GET` | `/buddy/voices/{voice_id}/sample` | Required | Get audio preview of a voice |

### Mental Health Dashboard  `/api/v1/mental-health`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/mental-health/dashboard?days=30` | Required | Returns aggregated mood data: daily scores, weekly/monthly averages, emotion distribution, recent sessions. `days=0` returns all-time data |

### Export  `/api/v1/export`

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `GET` | `/export/consultation/{id}/pdf` | Required | Download complete consultation report as a formatted PDF. Serves pre-built PDF from Supabase Storage if available, otherwise generates on-demand |

---

## Database Schema

The full schema is in [Backend/supabase_schema.sql](Backend/supabase_schema.sql). Key tables:

| Table | Description |
|-------|-------------|
| `users` | Core user accounts (email, password hash, name) |
| `profiles` | Comprehensive health profile (personal + 8 JSONB sections) |
| `consultations` | Named consultation groups per user |
| `sessions` | Individual doctor visit records inside a consultation |
| `session_documents` | Uploaded files with OCR text and Supabase Storage path |
| `conversations` | AI chat threads |
| `messages` | Individual messages within a conversation (user + assistant roles) |
| `emotional_sessions` | Buddy interactions with mood score, emotion probs, audio metadata |

---

## Getting Started

### Prerequisites

- **Flutter SDK** ≥ 3.5
- **Python** 3.11+
- A [Supabase](https://supabase.com) project (free tier works)
- A [Groq](https://console.groq.com) API key (free tier available)
- A [Qdrant Cloud](https://cloud.qdrant.io) cluster (free tier available)
- An [OpenAI](https://platform.openai.com) API key (for Whisper STT + TTS)

### 1. Supabase Setup

1. Create a new Supabase project.
2. Open the **SQL Editor** and run the full contents of [Backend/supabase_schema.sql](Backend/supabase_schema.sql).
3. Create a storage bucket named `documents` (for session document uploads) and `pdfs` (for exported consultation PDFs). Set both to private.
4. Note your **Project URL**, **Service Role Key**, and **Anon Key** from _Project Settings → API_.

### 2. Backend Setup

```bash
cd Backend

# Create and activate a virtual environment
python3 -m venv venv
source venv/bin/activate          # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set up environment variables
cp .env.example .env
# Edit .env with your credentials (see Environment Variables section below)

# Run the development server
uvicorn main:app --reload --port 8000
```

The API will be available at `http://localhost:8000`.  
Interactive docs: `http://localhost:8000/docs` (development mode only).

### 3. Flutter Setup

```bash
# From the project root
flutter pub get

# Generate code (Riverpod, Freezed, Retrofit, JSON serializers)
dart run build_runner build --delete-conflicting-outputs

# Run the app
flutter run
```

> **Android Emulator note:** The Dio client is pre-configured to use `http://10.0.2.2:8000/api/v1` which maps to your localhost from within the Android emulator.

> **Physical device:** Update the `baseUrl` in `lib/src/core/network/dio_client.dart` to your machine's local IP address (e.g. `http://192.168.x.x:8000/api/v1`).

---

## Environment Variables

Copy `Backend/.env.example` to `Backend/.env` and fill in all values:

```env
# ── Supabase ───────────────────────────────────────────────────
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...          # Found in Project Settings → API
SUPABASE_ANON_KEY=eyJ...

# ── Groq (LLM) ────────────────────────────────────────────────
GROQ_API_KEY=gsk_...
GROQ_MODEL=llama-3.3-70b-versatile

# ── Qdrant (Vector DB for RAG) ────────────────────────────────
QDRANT_URL=https://your-cluster.qdrant.io
QDRANT_API_KEY=...
QDRANT_COLLECTION=medical_rag

# ── OpenAI (Whisper STT + TTS) ───────────────────────────────
# Used via the openai Python SDK
OPENAI_API_KEY=sk-...                     # Set in your env or add to Settings

# ── Optional: Sarvam (Indian language TTS fallback) ──────────
SARVAM_API_KEY=                           # Leave empty to use OpenAI TTS only

# ── JWT Auth ──────────────────────────────────────────────────
JWT_SECRET_KEY=<generate: openssl rand -hex 32>
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=10080         # 7 days

# ── App ───────────────────────────────────────────────────────
APP_ENV=development                       # Set to "production" to hide /docs
CORS_ORIGINS=http://localhost,http://localhost:3000,http://10.0.2.2
```

> **Never commit `.env`** — it is already listed in `.gitignore`.

---

## Deployment

The backend is deployed on **HuggingFace Spaces**:

- **Space URL:** https://huggingface.co/spaces/SG2407/Aarogyan
- **API base URL:** `https://sg2407-aarogyan.hf.space/api/v1`

The project also includes a `Dockerfile` and configuration for **Railway** deployment.

### Deploy to Railway

1. Push the repo to GitHub.
2. Create a new Railway project linked to your GitHub repo.
3. Set all environment variables in the Railway dashboard.
4. Railway will build using the `Dockerfile` and start the server.

### Deploy to HuggingFace Spaces

1. Create a new Space (Docker SDK).
2. Push the `Backend/` folder contents to the Space repository.
3. Add all environment variables as Space Secrets.

---

## Design System

The Flutter app uses a custom **Material 3** theme (defined in `lib/src/core/theme/app_theme.dart`):

| Token | Value |
|-------|-------|
| Primary | `#1A6B5A` (teal green) |
| Secondary | `#E8F5F0` |
| Accent | `#F4845F` (warm orange) |
| Surface | `#FFFFFF` |
| Background | `#F7FAF9` |
| Error | `#D94F4F` |
| Text Primary | `#1A1A2E` |
| Text Secondary | `#6B7280` |
| Font | DM Sans (Google Fonts) |
| Border Radius | 16–24 px |
| Min Tap Target | 48 px |

Light and dark themes are supported, with the user's preference persisted via `shared_preferences`.

---

## License

MIT
