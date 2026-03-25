# Aarogyan — Full Project Explanation

---

## 1. What Is Aarogyan?

Aarogyan is an AI-powered personal health companion app. Users can:
- Manage their full medical profile (conditions, allergies, medications, lifestyle, etc.)
- Track consultations and doctor visits with session notes + document uploads
- Chat with an AI medical assistant that is personalised to their health profile
- Upload prescriptions / lab reports and get plain-language explanations
- Talk to an emotional companion (Orbz) via voice and track their mental wellness
- Export full consultation reports as PDFs

---

## 2. Project Structure (Diagrammatic)

```
aarogyan_be_project/
│
├── Backend/                         ← Python FastAPI backend
│   ├── main.py                      ← App entry point, router registration, CORS
│   ├── requirements.txt             ← Python dependencies
│   ├── .env                         ← Secret keys (Supabase, Groq, Qdrant, JWT)
│   ├── .env.example                 ← Template for .env
│   ├── supabase_schema.sql          ← Database table definitions
│   ├── Procfile                     ← Railway start command
│   ├── railway.toml                 ← Railway build config
│   ├── .railwayignore               ← Files excluded from Railway deploy
│   │
│   └── app/
│       ├── config.py                ← Settings/env-var loader (pydantic-settings)
│       ├── database.py              ← Supabase client singleton
│       ├── auth.py                  ← JWT creation, password hashing, auth dependency
│       │
│       ├── routers/                 ← API route handlers (one file per feature)
│       │   ├── auth.py              ← POST /auth/signup, POST /auth/login
│       │   ├── profile.py           ← GET/PUT /profile/me
│       │   ├── consultations.py     ← CRUD /consultations
│       │   ├── sessions.py          ← CRUD /consultations/{id}/sessions + document upload
│       │   ├── assistant.py         ← Conversations + /assistant/chat
│       │   ├── documents.py         ← POST /documents/summarise
│       │   ├── buddy.py             ← Voice + text emotional companion
│       │   ├── mental_health.py     ← GET /mental-health/dashboard
│       │   └── export.py            ← GET /export/consultation/{id}/pdf
│       │
│       └── services/                ← Business logic / AI / ML services
│           ├── ai.py                ← LLM calls: chat, document summary, buddy responses
│           ├── rag_pipeline.py      ← RAG: embed query → Qdrant search → rerank → context
│           ├── ocr.py               ← OCR: PDF/image → text (EasyOCR + PyMuPDF)
│           ├── stt.py               ← Speech-to-Text via OpenAI Whisper API
│           ├── tts.py               ← Text-to-Speech via OpenAI TTS API
│           ├── pdf_export.py        ← Generate formatted consultation PDF
│           └── profile_context.py   ← Serialise user profile into plain-text for LLM
│
│
└── lib/                             ← Flutter frontend (Dart)
    ├── main.dart                    ← App entry point: theme + provider + router setup
    │
    └── src/
        ├── core/
        │   ├── network/
        │   │   ├── dio_client.dart  ← Dio HTTP client with JWT interceptor
        │   │   └── token_storage.dart ← Secure storage for JWT token + user_id
        │   ├── router/
        │   │   └── app_router.dart  ← GoRouter: all routes + auth-guard redirect logic
        │   └── theme/
        │       ├── app_theme.dart   ← Material 3 light + dark theme (DM Sans font, teal)
        │       └── theme_provider.dart ← Riverpod notifier: persists light/dark preference
        │
        ├── features/
        │   ├── auth/
        │   │   ├── data/auth_repository.dart         ← login/signup API calls
        │   │   └── presentation/
        │   │       ├── auth_notifier.dart             ← Riverpod state: auth status
        │   │       ├── screens/splash_screen.dart     ← Loading screen during auth check
        │   │       ├── screens/login_screen.dart      ← Email + password login UI
        │   │       └── screens/signup_screen.dart     ← Registration UI
        │   │
        │   ├── home/
        │   │   ├── main_shell.dart                   ← Bottom-nav shell (wraps all tabs)
        │   │   └── home_screen.dart                  ← Dashboard home screen
        │   │
        │   ├── profile/
        │   │   ├── data/profile_repository.dart      ← getProfile / upsertProfile API calls
        │   │   └── presentation/screens/
        │   │       ├── profile_setup_screen.dart     ← Multi-step profile onboarding form
        │   │       └── profile_screen.dart           ← View/edit profile screen
        │   │
        │   ├── consultation/
        │   │   ├── data/consultation_repository.dart ← CRUD API for consultations + sessions
        │   │   └── presentation/screens/
        │   │       ├── consultations_screen.dart     ← List all consultations
        │   │       ├── consultation_detail_screen.dart ← Sessions inside a consultation
        │   │       └── session_detail_screen.dart    ← Single session: notes + documents
        │   │
        │   ├── assistant/
        │   │   ├── data/assistant_repository.dart    ← Conversations + chat API calls
        │   │   └── presentation/screens/
        │   │       ├── assistant_screen.dart         ← List past conversations
        │   │       └── chat_screen.dart              ← Chat UI with AI medical assistant
        │   │
        │   ├── document/
        │   │   ├── data/document_repository.dart     ← Upload + summarise document API call
        │   │   └── presentation/screens/
        │   │       └── document_screen.dart          ← Upload file, view OCR + summary
        │   │
        │   ├── buddy/
        │   │   ├── data/buddy_repository.dart        ← Voice/text buddy API calls
        │   │   └── presentation/screens/
        │   │       └── buddy_screen.dart             ← Voice companion UI (Orbz)
        │   │
        │   └── mental_health/
        │       ├── data/mental_health_repository.dart ← Dashboard data API call
        │       └── presentation/screens/
        │           └── mental_health_screen.dart     ← Mood charts + session history
        │
        └── shared/
            └── widgets/
                ├── app_button.dart      ← Reusable styled button
                ├── app_text_field.dart  ← Reusable styled text input
                └── section_header.dart ← Reusable section title widget
```

---

## 3. All API Endpoints

All endpoints are prefixed with `/api/v1`. Protected endpoints require the `Authorization: Bearer <JWT>` header.

### Auth  (`/api/v1/auth`)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/signup` | ❌ Public | Create a new account. Returns JWT token + user_id |
| POST | `/auth/login` | ❌ Public | Login with email + password. Returns JWT token + user_id |

### Profile  (`/api/v1/profile`)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/profile/me` | ✅ Required | Fetch logged-in user's complete health profile |
| PUT | `/profile/me` | ✅ Required | Create or update profile (upsert — all fields optional) |

**Profile data includes:** personal info (name, DOB, sex, height, weight, blood group), existing conditions, allergies, medications, supplements, past medical history, family history, lifestyle (activity, diet, sleep, smoking), mental health info.

### Consultations  (`/api/v1/consultations`)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/consultations/` | ✅ Required | List all consultations for the logged-in user |
| POST | `/consultations/` | ✅ Required | Create a new consultation (name, start date, notes) |
| GET | `/consultations/{id}` | ✅ Required | Get a single consultation by ID |
| PATCH | `/consultations/{id}` | ✅ Required | Update consultation fields |
| DELETE | `/consultations/{id}` | ✅ Required | Delete a consultation |

### Sessions  (`/api/v1/consultations/{consultation_id}/sessions`)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/sessions/` | ✅ Required | List all sessions inside a consultation (includes documents) |
| POST | `/sessions/` | ✅ Required | Create a session (visit date, symptoms, diagnosis, medications, notes) |
| GET | `/sessions/{session_id}` | ✅ Required | Get a single session with all its documents |
| PATCH | `/sessions/{session_id}` | ✅ Required | Update session fields |
| DELETE | `/sessions/{session_id}` | ✅ Required | Delete a session |
| POST | `/sessions/{session_id}/documents` | ✅ Required | Upload a PDF/JPG/PNG document; OCR text extracted automatically; file stored in Supabase Storage |
| DELETE | `/sessions/{session_id}/documents/{doc_id}` | ✅ Required | Delete a document (removes from Supabase Storage too) |

### Medical Assistant  (`/api/v1/assistant`)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/assistant/conversations` | ✅ Required | List all conversations for the user |
| POST | `/assistant/conversations` | ✅ Required | Create a new conversation |
| GET | `/assistant/conversations/{id}` | ✅ Required | Get conversation with full message history |
| DELETE | `/assistant/conversations/{id}` | ✅ Required | Delete a conversation |
| POST | `/assistant/chat` | ✅ Required | Send a message; AI responds using RAG + user profile context |

### Document Summarisation  (`/api/v1/documents`)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/documents/summarise` | ✅ Required | Upload a PDF/JPG/PNG; returns OCR-extracted text + structured AI summary |

### Emotional Buddy (Orbz)  (`/api/v1/buddy`)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/buddy/voice` | ✅ Required | Upload audio → STT → AI empathetic response → TTS → returns voice reply as base64 audio + mood score |
| GET | `/buddy/sessions` | ✅ Required | List all past buddy sessions |
| GET | `/buddy/sessions/{id}` | ✅ Required | Get individual buddy session |

### Mental Health Dashboard  (`/api/v1/mental-health`)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/mental-health/dashboard` | ✅ Required | Returns daily, weekly, monthly average mood scores + recent sessions |

### Export  (`/api/v1/export`)
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/export/consultation/{id}/pdf` | ✅ Required | Download complete consultation report as a formatted PDF file |

---

## 4. Tech Stack

### Backend
| Category | Technology | Purpose |
|----------|-----------|---------|
| Language | Python 3.13 | Core language |
| Web Framework | FastAPI | REST API, async request handling, OpenAPI docs |
| ASGI Server | Uvicorn + uvloop | High-performance async server |
| Database | Supabase (PostgreSQL) | All structured data (users, profiles, consultations, sessions, messages, moods) |
| File Storage | Supabase Storage | Uploaded documents (PDFs, images) |
| Authentication | JWT (python-jose) + bcrypt | Stateless token auth, secure password hashing |
| LLM (AI Chat / Summarisation) | Groq API (`llama-3.3-70b-versatile`) | Medical assistant chat, document summarisation, emotional buddy, query routing |
| RAG (Medical Knowledge) | Qdrant Cloud + BAAI/bge-small-en-v1.5 | Vector database of pre-ingested medical knowledge; semantic search over it |
| RAG Reranker | cross-encoder/ms-marco-MiniLM-L-6-v2 | Reranks top Qdrant hits for better relevance |
| OCR | EasyOCR + PyMuPDF (fitz) | Extracts text from uploaded PDF/image documents |
| Speech-to-Text | OpenAI Whisper API | Transcribes user voice audio to text |
| Text-to-Speech | OpenAI TTS API (nova voice) | Converts Orbz's text responses back to audio |
| PDF Generation | fpdf2 | Creates formatted consultation PDF reports |
| Config Management | pydantic-settings | Typed env-var loading from `.env` |
| Deployment | Railway (cloud) | Hosting via GitHub-connected service |

### Frontend
| Category | Technology | Purpose |
|----------|-----------|---------|
| Language | Dart | Core language |
| Framework | Flutter | Cross-platform UI (Android + iOS) |
| State Management | Riverpod (flutter_riverpod) | App-wide reactive state |
| HTTP Client | Dio | API requests with JWT interceptor |
| Routing | GoRouter | Declarative navigation with auth-guard redirects |
| Secure Storage | flutter_secure_storage | Stores JWT token and user_id encrypted on device |
| Local Preferences | shared_preferences | Persists light/dark theme choice |
| Fonts | Google Fonts (DM Sans) | App-wide typography |
| Design System | Material 3 | Component library with custom teal color scheme |

---

## 5. All Files Created — Backend

---

### `Backend/main.py`
**Role:** Entry point of the FastAPI application.
- Creates the FastAPI app instance with CORS middleware.
- Registers all 9 routers under the `/api/v1` prefix.
- Uses FastAPI's `lifespan` context manager to pre-warm the RAG models at startup (so the first actual query doesn't suffer cold-start delay).
- Controls whether `/docs` and `/redoc` OpenAPI pages are shown (only in `development` environment).
- **Data flow:** Request from Flutter → CORS check → auth middleware → routed to appropriate router.

---

### `Backend/app/config.py`
**Role:** Centralised settings loader.
- Defines a `Settings` class using pydantic-settings which automatically reads all variables from the `.env` file.
- Holds: Supabase credentials, Groq API key + model name, Qdrant URL/key/collection, JWT secret + algorithm, CORS origins, token expiry.
- Uses `@lru_cache` so `.env` is read only once for the entire lifetime of the app.
- **Data flow:** Any service that needs a secret calls `get_settings()`, which returns the same cached instance.

---

### `Backend/app/database.py`
**Role:** Supabase client singleton.
- Creates a single `supabase.Client` instance using the service-role key (which bypasses Row Level Security for server-side operations).
- Exposes `get_supabase()` — all routers call this to interact with the database.
- **Data flow:** Router calls `get_supabase()` → returns client → router calls `.table(...).select/insert/update/delete` → data goes to/from Supabase PostgreSQL.

---

### `Backend/app/auth.py`
**Role:** Authentication utilities.
- `hash_password()`: Hashes a plain-text password using bcrypt before storing in DB.
- `verify_password()`: Checks a plain password against the stored bcrypt hash at login.
- `create_access_token()`: Creates a signed JWT with the `user_id` as subject and a 7-day expiry.
- `decode_token()`: Verifies the JWT signature and extracts the `user_id`.
- `get_current_user_id()`: A FastAPI `Depends` injectable — every protected route uses this to extract the `user_id` from the `Authorization` header automatically.
- **Data flow:** Login/signup → JWT created → stored on device → every subsequent request → JWT extracted by `get_current_user_id` → `user_id` injected into route handler.

---

### `Backend/app/routers/auth.py`
**Role:** Handles user registration and login.
- `POST /auth/signup`: Checks if email exists → hashes password → inserts user into `users` table → returns JWT.
- `POST /auth/login`: Looks up user by email → verifies password → returns JWT.
- **Data flow:** Flutter sends `{email, password, full_name}` → stored in Supabase `users` table → JWT returned → Flutter stores it securely.

---

### `Backend/app/routers/profile.py`
**Role:** Manages the user's comprehensive health profile.
- `GET /profile/me`: Fetches the single row from the `profiles` table for the current user.
- `PUT /profile/me`: Upserts (create or update) the profile. Accepts all 9 sections of health data as optional fields.
- Serialises nested list/dict fields (e.g., `existing_conditions`, `allergies`) into JSONB for storage.
- **Data flow:** Flutter sends profile form data → upserted into Supabase `profiles` table → later retrieved and injected into AI prompts via `profile_context.py`.

---

### `Backend/app/routers/consultations.py`
**Role:** CRUD for consultations (a named grouping of medical visits, e.g., "Diabetes Management 2025").
- Full CRUD: list, create, get, update, delete.
- All operations are scoped to the logged-in user (`user_id` filter on every query).
- **Data flow:** Flutter → router → Supabase `consultations` table. Consultations act as the parent for sessions.

---

### `Backend/app/routers/sessions.py`
**Role:** Manages individual doctor visit sessions inside a consultation, plus document uploads.
- Full CRUD for sessions (visit date, symptoms, diagnosis, medications, doctor notes).
- `_verify_consultation_owner()` helper ensures users can only access sessions within their own consultations.
- `POST /sessions/{id}/documents`: Accepts a PDF/image upload → validates type + size → uploads file to Supabase Storage → calls OCR service to extract text → inserts metadata + OCR text into `session_documents` table.
- `DELETE /sessions/{id}/documents/{doc_id}`: Removes record from DB and the file from Supabase Storage.
- Each session GET returns its documents included (`session_documents(*)`).
- **Data flow:** Flutter uploads file → stored in Supabase Storage bucket `documents` → OCR text extracted → stored in `session_documents` table alongside the public URL.

---

### `Backend/app/routers/assistant.py`
**Role:** AI medical assistant with conversation history.
- Manages `conversations` (chat threads) in the `conversations` table.
- `POST /assistant/chat`: Main endpoint — receives a user message:
  1. Resolves or creates a conversation.
  2. Fetches the last 20 messages for context.
  3. Loads the user's health profile via `profile_context.py`.
  4. Routes query (General vs Detailed) via an LLM router.
  5. Calls `chat_with_ai()` which uses RAG for detailed queries, or direct LLM for general ones.
  6. Saves user message + AI response to the `messages` table.
  7. Updates the conversation `preview` field.
  8. Returns the AI response.
- **Data flow:** Flutter → message sent → profile fetched from DB → RAG retrieves medical context from Qdrant → LLM (Groq) generates response → messages saved to Supabase → response sent to Flutter.

---

### `Backend/app/routers/documents.py`
**Role:** Upload and summarise a medical document in one step.
- `POST /documents/summarise`: Accepts a file (PDF/JPG/PNG) → runs OCR → sends extracted text to `summarise_document()` in `ai.py` → returns structured JSON summary.
- Does NOT store anything — purely stateless analysis.
- **Data flow:** Flutter uploads document → OCR extracts text → LLM (Groq) analyses it and returns `{document_type, explanation, key_findings, action_items, disclaimer}` → Flutter displays summary.

---

### `Backend/app/routers/buddy.py`
**Role:** Emotional companion (Orbz) — voice and text interaction with mood tracking.
- `POST /buddy/voice`:
  1. Receives audio file.
  2. Sends to STT service (OpenAI Whisper) → gets user's transcribed text.
  3. Sends transcribed text to `emotional_buddy_respond()` in `ai.py` → gets empathetic text response + mood score (1–10).
  4. Sends AI text to TTS service (OpenAI TTS) → gets audio bytes.
  5. Saves complete interaction to `emotional_sessions` table.
  6. Returns: transcribed text, AI text, mood score, audio as base64.
- **Data flow:** User speaks → audio uploaded → STT → LLM → TTS → response audio returned + session saved to DB.

---

### `Backend/app/routers/mental_health.py`
**Role:** Mental wellness dashboard analytics.
- `GET /mental-health/dashboard`: Fetches all buddy sessions for the user → computes:
  - Daily average mood scores (keyed by `YYYY-MM-DD`)
  - Weekly average mood scores (keyed by ISO week)
  - Monthly average mood scores (keyed by `YYYY-MM`)
  - Total session count
  - Last 10 sessions (for display)
- **Data flow:** All buddy sessions from Supabase `emotional_sessions` → aggregated in Python → chart-ready data returned to Flutter.

---

### `Backend/app/routers/export.py`
**Role:** Generates and downloads a PDF consultation report.
- `GET /export/consultation/{id}/pdf`: Verifies ownership → fetches consultation + all sessions + all documents → calls `generate_consultation_pdf()` → streams PDF bytes as a downloadable response.
- **Data flow:** Flutter triggers download → all data fetched from Supabase → formatted PDF generated → streamed as `application/pdf` response → Flutter saves/shares the file.

---

### `Backend/app/services/ai.py`
**Role:** Central LLM service — all calls to the Groq API live here.
- `_call_groq()`: Low-level async function that makes the HTTP call to Groq's chat completions endpoint.
- `_route_query()`: Sends the user query to the LLM and asks it to classify it as "General" or "Detailed" (determines whether to use RAG or direct answer).
- `chat_with_ai()`: Orchestrates the full chat pipeline:
  - For **Detailed** queries → fetches RAG context from Qdrant → builds a context-rich system prompt → calls LLM → returns structured JSON response.
  - For **General** queries → uses the standard medical assistant system prompt with profile context → calls LLM → returns plain text.
- `summarise_document()`: Sends OCR text of a document to the LLM with a structured JSON response prompt → returns `{document_type, explanation, key_findings, action_items, disclaimer}`.
- `emotional_buddy_respond()`: Sends user text to the LLM with the Orbz empathetic companion system prompt → returns `{response, mood_score}`.
- **Data flow:** Called by routers → formats messages → POST to Groq API → parses JSON response → returns to router.

---

### `Backend/app/services/rag_pipeline.py`
**Role:** Retrieval-Augmented Generation (RAG) — fetches relevant medical knowledge to inform AI answers.
- At startup, `init_rag_models()` loads two models into memory:
  - `BAAI/bge-small-en-v1.5` — embedding model that converts text to a dense vector.
  - `cross-encoder/ms-marco-MiniLM-L-6-v2` — reranker that scores relevance of retrieved passages.
- `retrieve_context_rag()`: Given a user query:
  1. Embeds the query into a 384-dim vector.
  2. Queries Qdrant Cloud for the top-K most similar documents.
  3. For complex queries, reranks the results using the cross-encoder.
  4. Returns the top passages as a plain-text context block.
- **Data flow:** User query → embed → Qdrant similarity search → rerank → formatted text context → passed to `ai.py` for inclusion in LLM prompt.

---

### `Backend/app/services/ocr.py`
**Role:** Extracts text from uploaded PDF or image files.
- Uses PyMuPDF (`fitz`) to render each page of a PDF as a high-resolution image (2x scale for accuracy).
- Uses EasyOCR to read text from images.
- Both operations run in a thread pool executor so they don't block FastAPI's async event loop.
- Lazy-initialises the EasyOCR reader on first use (avoids slow startup).
- **Data flow:** File bytes + content type → PDF rendered page by page OR image loaded → EasyOCR reads text → joined string returned to router.

---

### `Backend/app/services/stt.py`
**Role:** Converts voice audio to text using OpenAI Whisper.
- Sends audio bytes (WAV, MP3, M4A, OGG, WebM) as a multipart form upload to the OpenAI `/v1/audio/transcriptions` endpoint.
- **Data flow:** Audio bytes from buddy router → POSTed to OpenAI Whisper → transcribed text string returned.

---

### `Backend/app/services/tts.py`
**Role:** Converts text to speech using OpenAI TTS.
- POSTs text to the OpenAI `/v1/audio/speech` endpoint using the `nova` voice (warm, friendly tone for Orbz).
- Returns raw MP3 audio bytes.
- **Data flow:** AI response text from buddy router → POSTed to OpenAI TTS → MP3 bytes returned → base64-encoded → sent to Flutter.

---

### `Backend/app/services/pdf_export.py`
**Role:** Generates a formatted PDF report of a full consultation.
- Defines `AarogyanPDF` class (extends fpdf2 `FPDF`) with custom header (teal title + line), footer (page number + date), section titles, and field rows.
- `generate_consultation_pdf()`: Iterates over all sessions and their documents, outputs:
  - Consultation name, date, notes
  - Each session: visit date, diagnosis, symptoms, medications, doctor notes
  - Each session's document filenames and OCR-extracted text
- Handles Unicode characters by translating them to ASCII equivalents (fpdf2 core fonts are latin-1 only).
- **Data flow:** Consultation + sessions data → formatted into PDF pages → returned as raw bytes → streamed to Flutter.

---

### `Backend/app/services/profile_context.py`
**Role:** Converts the user's database profile into a plain-text summary for the LLM.
- Reads the `profiles` table for the user.
- Formats personal details, conditions, allergies, medications, lifestyle, and mental health into readable lines.
- Calculates BMI from height and weight.
- **Data flow:** User ID in → Supabase profile fetched → plain-text string out → included in LLM system prompt so the AI gives personalised responses.

---

## 6. All Files Created — Flutter Frontend

---

### `lib/main.dart`
**Role:** Application entry point.
- Pre-loads the theme preference from shared_preferences before the app renders (prevents flash of wrong theme).
- Sets up `ProviderContainer` for Riverpod and wraps the entire app in `UncontrolledProviderScope`.
- Passes both `AppTheme.light` and `AppTheme.dark` themes to `MaterialApp.router`, controlled by `themeModeProvider`.
- **Data flow:** App launched → theme loaded from disk → Riverpod initialised → router and theme wired together → UI rendered.

---

### `lib/src/core/network/dio_client.dart`
**Role:** Central HTTP client configuration.
- Creates a `Dio` instance with the base URL (`http://10.0.2.2:8000/api/v1` for Android emulator).
- Attaches a request interceptor that reads the JWT token from `TokenStorage` and adds it as `Authorization: Bearer <token>` to every outgoing request automatically — so no individual screen has to handle auth headers.
- Exposed as a Riverpod `dioProvider` so any repository can inject it.
- **Data flow:** Repository makes API call → Dio interceptor attaches token → request sent to FastAPI backend.

---

### `lib/src/core/network/token_storage.dart`
**Role:** Secure local storage for authentication credentials.
- Uses `flutter_secure_storage` which encrypts data using the Android Keystore / iOS Keychain.
- Stores and retrieves: `access_token` (JWT) and `user_id`.
- `clear()` is called on logout to wipe all credentials.
- **Data flow:** Login succeeds → `saveToken()` called → token encrypted + stored → on next app launch, `getToken()` reads it → user stays logged in.

---

### `lib/src/core/router/app_router.dart`
**Role:** Declarative navigation with authentication guard.
- Defines all routes: `/splash`, `/auth/login`, `/auth/signup`, `/profile/setup`, `/home`, `/consultations`, `/consultations/:id`, `/consultations/:id/sessions/:sid`, `/assistant`, `/assistant/chat/:convId`, `/documents`, `/buddy`, `/mental-health`, `/profile`.
- The `redirect` function is called before every navigation:
  - If auth is still loading → stay on `/splash`.
  - If not authenticated and not on an auth page → redirect to `/auth/login`.
  - If authenticated and on auth/splash → redirect to `/home`.
- Uses `_AuthChangeNotifier` to rebuild the router whenever Riverpod's auth state changes.
- **Data flow:** User navigates OR auth state changes → redirect logic runs → correct screen shown.

---

### `lib/src/core/theme/app_theme.dart`
**Role:** Defines the visual design system.
- `AppColors`: Named constants for all brand colours (primary teal `#1A6B5A`, accent orange, backgrounds, error red, text colours).
- `AppTheme.light` and `AppTheme.dark`: Full Material 3 theme data with colour scheme, typography (DM Sans font), text styles, card styles, input decoration styles, etc.
- **Data flow:** Referenced by `main.dart` → passed to `MaterialApp` → all widgets automatically use these theme values.

---

### `lib/src/core/theme/theme_provider.dart`
**Role:** Manages and persists light/dark theme preference.
- `ThemeModeNotifier` is a Riverpod `Notifier<ThemeMode>`.
- `init()`: Reads stored preference from `SharedPreferences` at startup.
- `toggle()`: Switches theme and saves new preference to disk.
- **Data flow:** User toggles theme on profile screen → `toggle()` called → theme state updates → `MaterialApp` re-renders → new theme applied → preference saved to disk.

---

### `lib/src/features/auth/data/auth_repository.dart`
**Role:** Makes the actual HTTP calls for authentication.
- `signUp()`: POSTs to `/auth/signup`; on success, calls `TokenStorage.saveToken()`.
- `login()`: POSTs to `/auth/login`; on success, calls `TokenStorage.saveToken()`.
- **Data flow:** Notifier calls repository → repository calls backend API → JWT stored → notifier updates state.

---

### `lib/src/features/auth/presentation/auth_notifier.dart`
**Role:** Riverpod state management for authentication status.
- On startup (`build()`): reads token from `TokenStorage` — sets state to `authenticated` or `unauthenticated`.
- `signUp()` / `login()`: Calls repository, updates state to `authenticated` on success.
- `logout()`: Clears token storage, sets state to `unauthenticated`.
- Exposes `AuthStatus` enum (`unknown`, `authenticated`, `unauthenticated`) consumed by the router for redirects.
- **Data flow:** Auth state → router reacts → shows correct screen.

---

### `lib/src/features/auth/presentation/screens/splash_screen.dart`
**Role:** Loading screen shown while auth state is being resolved on startup.
- Shows the Aarogyan logo/branding.
- Stays on screen until the router redirect logic moves the user to login or home.

---

### `lib/src/features/auth/presentation/screens/login_screen.dart`
**Role:** Email + password login UI.
- Form with email and password fields, validation, login button.
- On submit: calls `authNotifier.login()` → on success, router auto-redirects to `/home`.
- Shows error message if login fails.

---

### `lib/src/features/auth/presentation/screens/signup_screen.dart`
**Role:** New user registration UI.
- Form with full name, email, password fields.
- On submit: calls `authNotifier.signUp()` → on success, router auto-redirects to `/home`.

---

### `lib/src/features/home/main_shell.dart`
**Role:** Persistent bottom navigation shell.
- Wraps all main feature screens.
- Bottom navigation bar with tabs: Home, Consultations, AI Assistant, Buddy, Profile.
- Keeps state of each tab alive using `IndexedStack`.

---

### `lib/src/features/home/home_screen.dart`
**Role:** Main dashboard screen.
- Shows a welcome greeting, quick-access cards to all features, and recent activity summary.

---

### `lib/src/features/profile/data/profile_repository.dart`
**Role:** API calls for profile management.
- `getProfile()`: GET `/profile/me`.
- `upsertProfile()`: PUT `/profile/me` with full profile data.
- **Data flow:** Profile screen loads → repository fetches from backend → displayed in form; on save → sent back.

---

### `lib/src/features/profile/presentation/screens/profile_setup_screen.dart`
**Role:** First-time multi-step onboarding form.
- Multi-page form covering all 9 profile sections (personal info, conditions, allergies, medications, supplements, past history, family history, lifestyle, mental health).
- On completion: submits to `PUT /profile/me`.

---

### `lib/src/features/profile/presentation/screens/profile_screen.dart`
**Role:** View and edit profile + settings.
- Displays current profile data.
- Includes the light/dark theme toggle.
- Logout button (clears token and redirects to login).

---

### `lib/src/features/consultation/data/consultation_repository.dart`
**Role:** All API calls for consultations and sessions.
- CRUD operations for consultations and sessions.
- `uploadDocument()`: Sends file as multipart to `/sessions/{id}/documents`.
- `exportPdf()`: Downloads PDF from `/export/consultation/{id}/pdf`.

---

### `lib/src/features/consultation/presentation/screens/consultations_screen.dart`
**Role:** Lists all of the user's consultations.
- Fetches from `GET /consultations/`.
- Create new consultation via dialog.
- Tap to navigate into `ConsultationDetailScreen`.

---

### `lib/src/features/consultation/presentation/screens/consultation_detail_screen.dart`
**Role:** Shows all sessions inside one consultation.
- Fetches sessions from `GET /consultations/{id}/sessions/`.
- Add new sessions.
- PDF download button.
- Tap session to navigate into `SessionDetailScreen`.

---

### `lib/src/features/consultation/presentation/screens/session_detail_screen.dart`
**Role:** Shows a single session's details and attached documents.
- Displays: visit date, symptoms, diagnosis, medications, doctor notes.
- Shows attached documents (with OCR text preview).
- Upload new document (PDF/JPG/PNG).
- Delete documents.

---

### `lib/src/features/assistant/data/assistant_repository.dart`
**Role:** API calls for the AI chat system.
- `listConversations()`, `createConversation()`, `getConversation()`, `deleteConversation()`.
- `sendMessage()`: POSTs to `/assistant/chat` and returns the AI's response.

---

### `lib/src/features/assistant/presentation/screens/assistant_screen.dart`
**Role:** Lists all past AI conversations.
- Tap to open a conversation in `ChatScreen`.
- Create a new conversation.
- Delete conversations.

---

### `lib/src/features/assistant/presentation/screens/chat_screen.dart`
**Role:** Real-time chat UI with the AI medical assistant.
- Message bubble list (user messages right-aligned, AI messages left-aligned).
- Text input bar.
- On send: calls `sendMessage()` → displays AI response.
- AI responses for RAG-based answers include a cited source disclaimer.

---

### `lib/src/features/document/data/document_repository.dart`
**Role:** API call for document summarisation.
- `summariseDocument()`: Sends PDF/image as multipart to `POST /documents/summarise`.

---

### `lib/src/features/document/presentation/screens/document_screen.dart`
**Role:** Upload any medical document for AI analysis.
- File picker to choose PDF or image.
- On upload: calls `summariseDocument()`.
- Displays the structured summary: document type, plain-language explanation, key findings, action items.

---

### `lib/src/features/buddy/data/buddy_repository.dart`
**Role:** API calls for the emotional companion (Orbz).
- `sendVoice()`: Sends audio file to `POST /buddy/voice`; returns AI voice response (as base64 audio) + mood score.
- `listSessions()`, `getSession()`.

---

### `lib/src/features/buddy/presentation/screens/buddy_screen.dart`
**Role:** Voice interaction UI for the emotional companion Orbz.
- Record button to capture user's voice.
- Plays back Orbz's audio response.
- Displays transcribed conversation.
- Shows mood score for the session.

---

### `lib/src/features/mental_health/data/mental_health_repository.dart`
**Role:** Fetches mental health dashboard data from the backend.
- `getDashboard()`: GET `/mental-health/dashboard`.

---

### `lib/src/features/mental_health/presentation/screens/mental_health_screen.dart`
**Role:** Mental wellness tracking dashboard.
- Line/bar charts for daily, weekly, and monthly mood scores.
- Summary stats (total sessions, trend).
- List of recent buddy sessions.
- **Data flow:** Backend computes averages from all buddy sessions → returned as `{daily_averages, weekly_averages, monthly_averages}` → Flutter renders as charts.

---

### `lib/src/shared/widgets/app_button.dart`
**Role:** Reusable styled primary button used across all screens. Handles loading state (shows spinner), disabled state, and consistent brand styling.

### `lib/src/shared/widgets/app_text_field.dart`
**Role:** Reusable styled text input field. Handles label, hint, error messages, obscure-text toggle (for passwords), and consistent border/focus styling.

### `lib/src/shared/widgets/section_header.dart`
**Role:** Reusable section title widget with optional "See all" action link. Used in lists and dashboard sections.

---

## 7. Database Tables (Supabase PostgreSQL)

| Table | What it stores |
|-------|---------------|
| `users` | id, email, password_hash, full_name, created_at |
| `profiles` | user_id, all health profile fields (personal, conditions, allergies, medications, etc.) as JSONB |
| `consultations` | id, user_id, name, start_date, notes, created_at |
| `sessions` | id, consultation_id, visit_date, symptoms, diagnosis, medications, doctor_notes |
| `session_documents` | id, session_id, file_name, storage_path, public_url, content_type, ocr_text |
| `conversations` | id, user_id, title, preview, created_at, updated_at |
| `messages` | id, conversation_id, role (user/assistant), content, created_at |
| `emotional_sessions` | id, user_id, user_text, buddy_text, mood_score (1–10), created_at |

---

## 8. End-to-End Data Flow Summary

```
Flutter App
    │
    │  (1) LOGIN: POST /api/v1/auth/login
    │      ← JWT token returned → stored in FlutterSecureStorage
    │
    │  (2) PROFILE: PUT /api/v1/profile/me
    │      → profile stored in Supabase 'profiles' table
    │
    │  (3) AI CHAT: POST /api/v1/assistant/chat
    │      → profile fetched from DB
    │      → LLM router classifies query as General/Detailed
    │      → if Detailed: bge-small embeds query → Qdrant search → cross-encoder rerank → context
    │      → Groq LLM generates answer using profile + RAG context
    │      → messages saved to 'messages' table
    │      ← AI response returned to Flutter
    │
    │  (4) DOCUMENT UPLOAD: POST /api/v1/documents/summarise
    │      → PDF/image bytes sent to backend
    │      → EasyOCR/PyMuPDF extract text
    │      → Groq LLM generates structured JSON summary
    │      ← {document_type, explanation, key_findings, action_items} returned
    │
    │  (5) BUDDY VOICE: POST /api/v1/buddy/voice
    │      → audio bytes sent
    │      → OpenAI Whisper transcribes speech to text
    │      → Groq LLM generates empathetic response + mood_score
    │      → OpenAI TTS converts response to MP3 audio
    │      → session saved to 'emotional_sessions' table
    │      ← {user_text, buddy_text, mood_score, audio_base64} returned
    │
    │  (6) PDF EXPORT: GET /api/v1/export/consultation/{id}/pdf
    │      → consultation + sessions + documents fetched from Supabase
    │      → fpdf2 generates formatted PDF
    │      ← PDF binary streamed back to Flutter
    │
FastAPI Backend ← → Supabase (PostgreSQL + Storage)
                ← → Groq API (Llama 3.3 70B)
                ← → Qdrant Cloud (vector DB)
                ← → OpenAI API (Whisper STT + TTS)
```
