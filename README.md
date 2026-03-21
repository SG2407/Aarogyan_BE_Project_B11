# Aarogyan — AI-Powered Health Companion

Aarogyan is a full-stack mobile health application built with **Flutter** (frontend) and **FastAPI** (backend). It provides an AI medical assistant, document scanning, emotional wellness buddy, mental health tracking, and consultation management.

---

## Features

| Feature | Description |
|---|---|
| **AI Medical Assistant** | Chat with an LLM-powered health assistant (via Groq) |
| **Document Scanner** | Scan and summarise prescriptions / lab reports using OCR + AI |
| **Emotional Buddy (Orbz)** | Voice-based emotional wellness companion with mood tracking |
| **Mental Health Dashboard** | Track mood scores and wellness trends over time |
| **Consultations** | Book and manage doctor consultations |
| **Health Profile** | Store detailed health profile (conditions, medications, lifestyle) |

---

## Tech Stack

### Frontend
- **Flutter** (Dart) — cross-platform mobile app
- **Riverpod** — state management
- **GoRouter** — navigation
- **Dio** — HTTP client
- **Supabase** — auth & database client

### Backend
- **FastAPI** (Python) — REST API
- **Supabase** — PostgreSQL database + auth
- **Groq API** — LLM inference (`llama-3.3-70b-versatile`)
- **JWT** — token-based auth

---

## Project Structure

```
aarogyan_be_project/
├── lib/                        # Flutter app
│   └── src/
│       ├── core/               # Theme, router, network, shared widgets
│       └── features/           # auth, profile, assistant, buddy, health, consultations
├── Backend/                    # FastAPI server
│   ├── app/
│   │   ├── routers/            # API route handlers
│   │   ├── services/           # AI service (Groq)
│   │   ├── auth.py             # JWT + bcrypt auth
│   │   └── config.py           # Settings (pydantic-settings)
│   ├── main.py
│   ├── requirements.txt
│   └── .env.example            # Environment variable template
└── android/ ios/ web/ ...      # Flutter platform targets
```

---

## Getting Started

### Prerequisites
- Flutter SDK ≥ 3.x
- Python 3.11+
- A [Supabase](https://supabase.com) project
- A free [Groq](https://console.groq.com) API key

### Backend Setup

```bash
cd Backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Copy and fill in environment variables
cp .env.example .env
# Edit .env with your Supabase + Groq credentials

uvicorn main:app --reload
```

### Flutter Setup

```bash
flutter pub get
flutter run
```

> **Android Emulator**: the backend URL is set to `http://10.0.2.2:8000/api/v1` which maps to your Mac's localhost.

---

## Environment Variables

Copy `Backend/.env.example` to `Backend/.env` and fill in the values:

```env
# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=...
SUPABASE_ANON_KEY=...

# Groq
GROQ_API_KEY=gsk_...
GROQ_MODEL=llama-3.3-70b-versatile

# JWT
JWT_SECRET_KEY=<run: openssl rand -hex 32>
JWT_ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=10080
```

> **Never commit `.env`** — it is listed in `.gitignore`.

---

## License

MIT
