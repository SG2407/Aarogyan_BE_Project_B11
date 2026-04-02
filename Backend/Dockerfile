FROM python:3.11-slim

# ── 1. System dependencies ────────────────────────────────────────────────────
# libglib2.0-0, libgl1, libsm6, libxext6, libxrender1 : required by EasyOCR / OpenCV
# libgomp1 : required by torch / scikit-learn OpenMP
# git      : huggingface_hub may need it for model snapshots
RUN apt-get update && apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libgomp1 \
    libgl1 \
    libsm6 \
    libxext6 \
    libxrender1 \
    libsndfile1 \
    git \
    && rm -rf /var/lib/apt/lists/*

# ── 2. Non-root user (HF Spaces requirement) ──────────────────────────────────
RUN useradd -m -u 1000 user
USER user

ENV HOME=/home/user \
    PATH=/home/user/.local/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/home/user/.cache/huggingface

WORKDIR $HOME/app

# ── 3. Python dependencies ────────────────────────────────────────────────────
# Install CPU-only torch first from PyTorch index (~300 MB vs ~2 GB for GPU wheels)
COPY --chown=user requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
        torch==2.10.0 torchvision==0.25.0 \
        --index-url https://download.pytorch.org/whl/cpu && \
    grep -v -E "^torch==|^torchvision==" requirements.txt > /tmp/requirements_no_torch.txt && \
    pip install --no-cache-dir -r /tmp/requirements_no_torch.txt

# ── 4. Pre-download ML models at BUILD time ───────────────────────────────────
# Network is available here; models are written to $HF_HOME and cached in the
# Docker layer. At runtime TRANSFORMERS_OFFLINE=1 ensures no re-download.
RUN python -c "\
from sentence_transformers import SentenceTransformer; \
SentenceTransformer('BAAI/bge-small-en-v1.5'); \
print('SentenceTransformer cached'); \
from transformers import AutoTokenizer, AutoModelForSequenceClassification; \
AutoTokenizer.from_pretrained('cross-encoder/ms-marco-MiniLM-L-6-v2'); \
AutoModelForSequenceClassification.from_pretrained('cross-encoder/ms-marco-MiniLM-L-6-v2'); \
print('CrossEncoder cached'); \
from transformers import pipeline as _p; \
_p('text-classification', model='j-hartmann/emotion-english-distilroberta-base', top_k=None); \
print('Emotion classifier cached'); \
_p('audio-classification', model='superb/wav2vec2-base-superb-er'); \
print('Audio emotion classifier cached')"

# ── 5. Pre-download EasyOCR models ────────────────────────────────────────────
RUN python -c "\
import easyocr; \
easyocr.Reader(['en'], download_enabled=True); \
print('EasyOCR models cached')"

# ── 6. Lock runtime to offline mode ──────────────────────────────────────────
# Prevents any accidental re-download at runtime (also avoids timeout errors)
ENV TRANSFORMERS_OFFLINE=1 \
    HF_HUB_OFFLINE=1 \
    APP_ENV=production

# ── 7. Copy application code ──────────────────────────────────────────────────
# Intentionally AFTER model layers — code changes don't invalidate model cache
COPY --chown=user . .

EXPOSE 7860

# ── 8. Start server ───────────────────────────────────────────────────────────
CMD uvicorn main:app --host 0.0.0.0 --port "${PORT:-7860}" --workers 1
