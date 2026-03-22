import logging
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
from app.auth import get_current_user_id
from app.services.ocr import extract_text_from_file
from app.services.ai import summarise_document

logger = logging.getLogger("app.documents")

router = APIRouter(prefix="/documents", tags=["document-summarisation"])

ALLOWED_TYPES = {"application/pdf", "image/jpeg", "image/png"}
MAX_FILE_SIZE = 1536 * 1024  # 1.5 MB

_EXT_TO_MIME = {
    ".pdf": "application/pdf",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
}


@router.post("/summarise")
async def summarise(
    file: UploadFile = File(...),
    user_id: str = Depends(get_current_user_id),
):
    # Resolve content type — infer from filename if Dio sends wrong/missing type
    content_type = file.content_type or ""
    if content_type not in ALLOWED_TYPES and file.filename:
        ext = ("." + file.filename.rsplit(".", 1)[-1].lower()) if "." in file.filename else ""
        content_type = _EXT_TO_MIME.get(ext, content_type)

    logger.info("Document upload: filename=%s resolved_ct=%s", file.filename, content_type)

    if content_type not in ALLOWED_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Only PDF, JPG, PNG allowed (received '{file.content_type}')",
        )

    contents = await file.read()
    logger.info("File size: %.1f KB", len(contents) / 1024)
    if len(contents) > MAX_FILE_SIZE:
        raise HTTPException(status_code=400, detail="File exceeds 1.5 MB limit. Please upload a smaller document.")

    ocr_text = await extract_text_from_file(contents, content_type)
    if not ocr_text.strip():
        raise HTTPException(status_code=422, detail="No text could be extracted from document")

    summary = await summarise_document(ocr_text)
    return {
        "ocr_text": ocr_text,
        "summary": summary,
    }
