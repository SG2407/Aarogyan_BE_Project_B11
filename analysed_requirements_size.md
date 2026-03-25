# Requirements Analysis — Aarogyan Backend

> Analysed against all imports in `Backend/app/**/*.py` and `Backend/main.py`.
> Sizes measured from macOS venv (`Backend/venv/lib/python3.13/site-packages/`).
> **Note:** `torch` CUDA wheels on Linux are ~4 GB; macOS size shown here is ~397 MB.

---

## Summary

| Category | Count | Total Size (approx.) |
|---|---|---|
| Required | ~110 | ~800 MB (macOS) / ~5 GB+ (Linux CUDA) |
| NOT Required | 34 | ~300+ MB |
| Optional | 1 | ~68 MB |

---

## Key Findings

1. **`chromadb==1.5.5`** — **NEVER imported anywhere** in the codebase. It is the root cause of ~34 unnecessary packages and ~300+ MB of bloat (grpcio, kubernetes, opentelemetry-*, and more).
2. **`openai` SDK** — **NEVER imported**. All Groq, Whisper, and TTS calls are made via `httpx` directly.
3. **`torch`** — Required by `easyocr` and `sentence-transformers`. On Linux with CUDA wheels, this is ~4 GB — the primary blocker for Railway's 4 GB Docker image limit.
4. **`onnxruntime`** — Optional. EasyOCR defaults to `torch` backend; `onnxruntime` is only needed if explicitly switching EasyOCR to ONNX mode.

---

## NOT Required Packages (34 total)

These packages are safe to remove. All trace back to `chromadb` or the `openai` SDK being listed but never imported.

| Package | Size (macOS) | Reason Not Needed |
|---|---|---|
| `chromadb==1.5.5` | ~52 MB (incl. rust bindings) | Never imported anywhere |
| `grpcio==1.72.0` | ~38 MB | chromadb dependency |
| `kubernetes==32.0.1` | ~35 MB | chromadb dependency |
| `opentelemetry-sdk==1.34.1` | ~8 MB | chromadb dependency |
| `opentelemetry-api==1.34.1` | ~4 MB | chromadb dependency |
| `opentelemetry-exporter-otlp-proto-grpc==1.34.1` | ~3 MB | chromadb dependency |
| `opentelemetry-exporter-otlp-proto-common==1.34.1` | ~2 MB | chromadb dependency |
| `opentelemetry-instrumentation==0.55b1` | ~2 MB | chromadb dependency |
| `opentelemetry-instrumentation-asgi==0.55b1` | ~1 MB | chromadb dependency |
| `opentelemetry-instrumentation-fastapi==0.55b1` | ~1 MB | chromadb dependency |
| `opentelemetry-semantic-conventions==0.55b1` | ~1 MB | chromadb dependency |
| `opentelemetry-util-http==0.55b1` | ~0.5 MB | chromadb dependency |
| `openai==1.86.0` | ~13 MB | Never imported; httpx used directly |
| `pyiceberg==0.9.1` | ~10 MB | chromadb dependency |
| `Pygments==2.19.1` | ~9.1 MB | chromadb dependency (rich) |
| `typer==0.16.0` | ~2 MB | chromadb dependency |
| `rich==14.0.0` | ~6 MB | chromadb dependency |
| `strictyaml==1.7.3` | ~1 MB | chromadb dependency |
| `markdown-it-py==3.0.0` | ~1 MB | chromadb → rich dependency |
| `mdurl==0.1.2` | ~0.2 MB | chromadb → rich dependency |
| `PyPika==0.48.9` | ~1 MB | chromadb dependency |
| `mmh3==5.1.0` | ~0.5 MB | chromadb dependency |
| `overrides==7.7.0` | ~0.5 MB | chromadb dependency |
| `durationpy==0.9` | ~0.1 MB | chromadb → kubernetes dependency |
| `pyroaring==1.0.2` | ~1 MB | chromadb dependency |
| `oauthlib==3.2.2` | ~1 MB | chromadb → kubernetes dependency |
| `requests-oauthlib==2.0.0` | ~0.5 MB | chromadb → kubernetes dependency |
| `websocket-client==1.8.0` | ~1 MB | chromadb → kubernetes dependency |
| `shellingham==1.5.4` | ~0.3 MB | chromadb → typer dependency |
| `build==1.2.2` | ~1 MB | Dev/build tool, not runtime |
| `pyproject_hooks==1.2.0` | ~0.3 MB | Dev/build tool, not runtime |
| `ninja==1.11.1.4` | ~0.3 MB | Dev/build tool, not runtime |
| `aiofiles==24.1.0` | ~0.5 MB | Never imported anywhere |
| `zstandard==0.23.0` | ~2 MB | Never imported (chromadb dep) |

---

## Optional Package

| Package | Size (macOS) | Notes |
|---|---|---|
| `onnxruntime==1.22.0` | ~68 MB | Only needed if EasyOCR is explicitly configured to use ONNX backend. EasyOCR defaults to `torch`. Safe to remove unless ONNX inference is intended. |

---

## Required Packages (all actively imported)

### Large Packages (>10 MB)

| Package | Size (macOS) | Used By |
|---|---|---|
| `torch==2.10.0` | ~397 MB macOS / **~4 GB Linux CUDA** | easyocr, sentence-transformers |
| `opencv-python-headless` (cv2) | ~119 MB | `app/services/ocr.py` |
| `transformers==4.52.4` | ~119 MB | sentence-transformers |
| `scipy==1.15.3` | ~97 MB | sentence-transformers / sklearn |
| `sympy==1.14.0` | ~72 MB | torch dependency |
| `pymupdf==1.27.2.2` | ~56 MB | `app/services/ocr.py` — PDF page rendering |
| `scikit-learn` (sklearn) | ~45 MB | sentence-transformers (cross-encoder) |
| `numpy==2.2.6` | ~32 MB | ocr.py, rag_pipeline.py |
| `scikit-image` (skimage) | ~28 MB | easyocr dependency |
| `sentence-transformers==5.3.0` | ~4.3 MB | `app/services/rag_pipeline.py` — embeddings + reranking |

### Medium Packages (1–10 MB)

| Package | Size (macOS) | Used By |
|---|---|---|
| `pydantic-core==2.33.2` | ~4.5 MB | pydantic (all schemas) |
| `pydantic==2.11.5` | ~4 MB | all routers and services |
| `fastapi==0.135.1` | ~1.5 MB | `main.py` — core web framework |
| `starlette` | ~1.5 MB | fastapi dependency |
| `bcrypt==5.0.0` | ~1.2 MB | `app/auth.py` — password hashing |
| `uvicorn==0.34.3` | ~0.7 MB | `main.py` — ASGI server |
| `httpx==0.28.1` | ~0.7 MB | all services (Groq, STT, TTS calls) |
| `requests==2.32.3` | ~0.5 MB | qdrant-client dependency |
| `python-jose==3.5.0` | ~1 MB | `app/auth.py` — JWT creation/decoding |
| `qdrant-client==1.17.1` | ~2 MB | `app/services/rag_pipeline.py` |
| `easyocr==1.7.2` | ~2 MB | `app/services/ocr.py` |
| `fpdf2==2.8.7` | ~3 MB | `app/services/pdf_export.py` |
| `pydantic-settings==2.13.1` | ~0.5 MB | `app/config.py` |
| `python-multipart` | ~0.5 MB | fastapi file uploads (sessions router) |
| `pillow` | ~5 MB | easyocr dependency |

### Small Packages (<1 MB)

| Package | Size (macOS) | Used By |
|---|---|---|
| `supabase==2.28.3` | ~0.16 MB | `app/database.py` + all routers |
| `gotrue` | ~0.5 MB | supabase dependency |
| `postgrest-py` | ~0.4 MB | supabase dependency |
| `realtime` | ~0.3 MB | supabase dependency |
| `storage3` | ~0.3 MB | supabase (file uploads) |
| `anyio` | ~0.5 MB | httpx/fastapi dependency |
| `sniffio` | ~0.1 MB | anyio dependency |
| `certifi` | ~0.3 MB | requests/httpx dependency |
| `charset-normalizer` | ~0.5 MB | requests dependency |
| `idna` | ~0.4 MB | requests/httpx dependency |
| `urllib3` | ~0.4 MB | requests dependency |
| `h11` | ~0.2 MB | httpx/uvicorn dependency |
| `httpcore` | ~0.3 MB | httpx dependency |
| `click` | ~0.5 MB | uvicorn dependency |
| `annotated-types` | ~0.1 MB | pydantic dependency |
| `typing-extensions` | ~0.3 MB | pydantic/fastapi dependency |
| `cryptography` | ~2 MB | python-jose dependency |
| `cffi` | ~0.5 MB | cryptography dependency |
| `pycparser` | ~0.5 MB | cffi dependency |
| `ecdsa` | ~0.5 MB | python-jose dependency |
| `pyasn1` | ~0.3 MB | python-jose dependency |
| `rsa` | ~0.2 MB | python-jose dependency |
| `six` | ~0.1 MB | python-jose dependency |
| `tqdm` | ~0.3 MB | easyocr / sentence-transformers |
| `filelock` | ~0.1 MB | transformers dependency |
| `huggingface-hub` | ~1 MB | sentence-transformers / transformers |
| `tokenizers` | ~3 MB | transformers dependency |
| `safetensors` | ~1 MB | transformers dependency |
| `regex` | ~0.8 MB | transformers dependency |
| `PyYAML` | ~0.5 MB | transformers dependency |
| `packaging` | ~0.2 MB | transformers / sentence-transformers |
| `fsspec` | ~1 MB | transformers dependency |
| `networkx` | ~3 MB | torch dependency |
| `jinja2` | ~0.5 MB | torch dependency |
| `MarkupSafe` | ~0.2 MB | jinja2 dependency |
| `mpmath` | ~5 MB | sympy / torch dependency |
| `torchvision==0.25.0` | ~8 MB | easyocr dependency |
| `ninja` (torch build) | — | build-time only |
| `Shapely` | ~5 MB | easyocr dependency |
| `pyclipper` | ~0.5 MB | easyocr dependency |
| `imageio` | ~1 MB | scikit-image dependency |
| `lazy_loader` | ~0.1 MB | scikit-image dependency |
| `tifffile` | ~1 MB | scikit-image dependency |
| `threadpoolctl` | ~0.2 MB | scikit-learn dependency |
| `joblib` | ~1 MB | scikit-learn dependency |
| `python-dotenv` | ~0.2 MB | pydantic-settings dependency |
| `deprecation` | ~0.1 MB | supabase dependency |
| `httpx-sse` | ~0.1 MB | supabase dependency |
| `websockets` | ~0.5 MB | supabase/realtime dependency |
| `h2` | ~0.3 MB | httpx optional HTTP/2 |
| `hpack` | ~0.2 MB | h2 dependency |
| `hyperframe` | ~0.1 MB | h2 dependency |
| `exceptiongroup` | ~0.1 MB | anyio dependency |

---

## Deployment Options Based on This Analysis

### Option A — Oracle Cloud Always Free (Recommended)
No changes needed. The ~9 GB install fits on Oracle's 200 GB VM disk. No Docker image size limits.

### Option B — Remove Unnecessary Packages for Railway (4 GB limit)
Remove all 34 NOT Required packages. The key removal is just one line in `requirements.txt`:
```
chromadb==1.5.5
```
...and its entire dependency chain (see table above). Also remove `openai==1.86.0`, `aiofiles`, `build`, `pyproject_hooks`, `ninja`.

### Option C — CPU-only torch for Railway
Change `torch` to CPU-only wheels to save ~3.5 GB on Linux:
```
# Add to top of requirements.txt:
--extra-index-url https://download.pytorch.org/whl/cpu

# Change:
torch==2.6.0+cpu        # was torch==2.10.0
torchvision==0.21.0+cpu # was torchvision==0.25.0
```
Combine with Option B to bring total Docker image under Railway's 4 GB limit.
