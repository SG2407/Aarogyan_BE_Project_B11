"""Qdrant Cloud RAG pipeline — query-only (data is pre-ingested in Qdrant Cloud)."""
from __future__ import annotations

import json as _json
import logging
import asyncio
import threading
from concurrent.futures import ThreadPoolExecutor

from qdrant_client import QdrantClient
from sentence_transformers import SentenceTransformer, CrossEncoder

from app.config import get_settings

logger = logging.getLogger(__name__)

_EMBED_MODEL_NAME = "BAAI/bge-small-en-v1.5"
_RERANK_MODEL_NAME = "cross-encoder/ms-marco-MiniLM-L-6-v2"

_embed_model: SentenceTransformer | None = None
_rerank_model: CrossEncoder | None = None
_qdrant_client: QdrantClient | None = None
_executor = ThreadPoolExecutor(max_workers=2)
_load_lock = threading.Lock()


def _load_models() -> None:
    """Load embedding and reranking models (blocking — called once)."""
    global _embed_model, _rerank_model
    logger.info("Loading embedding model %s …", _EMBED_MODEL_NAME)
    _embed_model = SentenceTransformer(_EMBED_MODEL_NAME)
    logger.info("Loading reranker %s …", _RERANK_MODEL_NAME)
    _rerank_model = CrossEncoder(_RERANK_MODEL_NAME)
    logger.info("RAG models loaded successfully.")


def _ensure_models_loaded() -> None:
    """Thread-safe lazy loader — no-op if models are already in memory."""
    global _embed_model, _rerank_model
    if _embed_model is not None and _rerank_model is not None:
        return
    with _load_lock:
        # Double-check inside the lock
        if _embed_model is None or _rerank_model is None:
            _load_models()


def _get_qdrant() -> QdrantClient:
    global _qdrant_client
    if _qdrant_client is None:
        settings = get_settings()
        _qdrant_client = QdrantClient(
            url=settings.qdrant_url,
            api_key=settings.qdrant_api_key,
            timeout=15,
        )
    return _qdrant_client


async def init_rag_models() -> None:
    """Load models in a thread so the event loop is never blocked.
    Safe to call multiple times — _ensure_models_loaded() is idempotent.
    """
    loop = asyncio.get_event_loop()
    await loop.run_in_executor(_executor, _ensure_models_loaded)


def _retrieve_sync(
    query: str,
    top_k_fetch: int,
    top_k_return: int,
    is_complex: bool,
) -> tuple[str, list[str]]:
    """Synchronous Qdrant search + optional cross-encoder rerank.
    Lazy-loads models on first call if background loading hasn't finished yet.
    """
    _ensure_models_loaded()

    settings = get_settings()
    query_vec = _embed_model.encode(query, normalize_embeddings=True).tolist()

    result = _get_qdrant().query_points(
        collection_name=settings.qdrant_collection,
        query=query_vec,
        limit=top_k_fetch,
        with_payload=True,
    )
    hits = result.points

    if not hits:
        logger.info("Qdrant returned 0 hits for query: %r", query[:80])
        return "", []

    logger.info("Qdrant returned %d hits for query: %r", len(hits), query[:80])

    texts: list[str] = []
    sources: list[str] = []
    for hit in hits:
        payload = hit.payload
        # Text is stored inside _node_content as a LlamaIndex TextNode JSON
        raw_node = payload.get("_node_content", "")
        if raw_node:
            try:
                text = _json.loads(raw_node).get("text", "").strip()
            except (_json.JSONDecodeError, AttributeError):
                text = ""
        else:
            text = payload.get("text", "").strip()
        # Use the PDF file name as the human-readable source
        source = payload.get("file_name", payload.get("source", ""))
        texts.append(text)
        sources.append(source)

    if is_complex and len(texts) > top_k_return:
        pairs = [(query, t) for t in texts]
        scores = _rerank_model.predict(pairs)
        ranked = sorted(zip(scores, texts, sources), reverse=True)
        texts = [t for _, t, _ in ranked[:top_k_return]]
        sources = [s for _, _, s in ranked[:top_k_return]]
    else:
        texts = texts[:top_k_return]
        sources = sources[:top_k_return]

    context = "\n\n---\n\n".join(t for t in texts if t)
    unique_sources = list(dict.fromkeys(s for s in sources if s))
    return context, unique_sources


async def retrieve_context_rag(
    query: str,
    is_complex: bool = False,
    top_k_fetch: int = 8,
    top_k_return: int = 3,
) -> tuple[str, list[str]]:
    """Async retrieval — runs blocking search in thread executor."""
    loop = asyncio.get_event_loop()
    return await loop.run_in_executor(
        _executor,
        _retrieve_sync,
        query,
        top_k_fetch,
        top_k_return,
        is_complex,
    )
