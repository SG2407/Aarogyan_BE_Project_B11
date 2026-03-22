import io
import asyncio
import fitz  # PyMuPDF
import easyocr
from PIL import Image
import numpy as np

# Lazy-init EasyOCR reader (downloads model on first use)
_reader = None


def _get_reader():
    global _reader
    if _reader is None:
        _reader = easyocr.Reader(["en"], gpu=False)
    return _reader


async def extract_text_from_file(file_bytes: bytes, content_type: str) -> str:
    """Extract text from PDF or image — runs in a thread pool so the event loop stays unblocked."""
    loop = asyncio.get_running_loop()
    if content_type == "application/pdf":
        return await loop.run_in_executor(None, _extract_from_pdf, file_bytes)
    else:
        return await loop.run_in_executor(None, _extract_from_image, file_bytes)


def _extract_from_pdf(pdf_bytes: bytes) -> str:
    """Render each PDF page as image and run EasyOCR."""
    reader = _get_reader()
    doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    all_text = []

    for page_num in range(len(doc)):
        page = doc.load_page(page_num)
        # Render at 2x resolution for better OCR accuracy
        mat = fitz.Matrix(2.0, 2.0)
        pix = page.get_pixmap(matrix=mat)
        img_bytes = pix.tobytes("png")

        img = Image.open(io.BytesIO(img_bytes)).convert("RGB")
        img_np = np.array(img)

        results = reader.readtext(img_np, detail=0, paragraph=True)
        all_text.extend(results)

    doc.close()
    return "\n".join(all_text)


def _extract_from_image(image_bytes: bytes) -> str:
    """Run EasyOCR on a single image."""
    reader = _get_reader()
    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    img_np = np.array(img)
    results = reader.readtext(img_np, detail=0, paragraph=True)
    return "\n".join(results)
