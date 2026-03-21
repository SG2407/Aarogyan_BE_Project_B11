from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
from app.auth import get_current_user_id
from app.services.ocr import extract_text_from_file
from app.services.ai import summarise_document

router = APIRouter(prefix="/documents", tags=["document-summarisation"])

ALLOWED_TYPES = {"application/pdf", "image/jpeg", "image/png"}
MAX_FILE_SIZE = 2 * 1024 * 1024


@router.post("/summarise")
async def summarise(
    file: UploadFile = File(...),
    user_id: str = Depends(get_current_user_id),
):
    if file.content_type not in ALLOWED_TYPES:
        raise HTTPException(status_code=400, detail="Only PDF, JPG, PNG allowed")

    contents = await file.read()
    if len(contents) > MAX_FILE_SIZE:
        raise HTTPException(status_code=400, detail="File exceeds 2 MB limit")

    ocr_text = await extract_text_from_file(contents, file.content_type)
    if not ocr_text.strip():
        raise HTTPException(status_code=422, detail="No text could be extracted from document")

    summary = await summarise_document(ocr_text)
    return {
        "ocr_text": ocr_text,
        "summary": summary,
    }
