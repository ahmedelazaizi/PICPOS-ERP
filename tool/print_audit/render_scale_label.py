"""Render the generated scale-label PDF and crop its first label."""
from __future__ import annotations

import ctypes
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PDF = ROOT / "docs/plans/scale_label_2026-11-03/scale_label_preview.pdf"
OUT = PDF.parent
PDFIUM = ROOT / "build/windows/x64/pdfium-src/bin/pdfium.dll"


def render_page(pdf_path: Path, scale: float = 2.2) -> Image.Image:
    pdfium = ctypes.CDLL(str(PDFIUM))
    handle = ctypes.c_void_p
    pdfium.FPDF_InitLibrary()
    pdfium.FPDF_LoadDocument.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
    pdfium.FPDF_LoadDocument.restype = handle
    pdfium.FPDF_GetPageCount.argtypes = [handle]
    pdfium.FPDF_GetPageCount.restype = ctypes.c_int
    pdfium.FPDF_LoadPage.argtypes = [handle, ctypes.c_int]
    pdfium.FPDF_LoadPage.restype = handle
    pdfium.FPDF_GetPageWidthF.argtypes = [handle]
    pdfium.FPDF_GetPageWidthF.restype = ctypes.c_float
    pdfium.FPDF_GetPageHeightF.argtypes = [handle]
    pdfium.FPDF_GetPageHeightF.restype = ctypes.c_float
    pdfium.FPDFBitmap_Create.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int]
    pdfium.FPDFBitmap_Create.restype = handle
    pdfium.FPDFBitmap_FillRect.argtypes = [handle, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_uint]
    pdfium.FPDFBitmap_GetBuffer.argtypes = [handle]
    pdfium.FPDFBitmap_GetBuffer.restype = ctypes.POINTER(ctypes.c_ubyte)
    pdfium.FPDFBitmap_GetStride.argtypes = [handle]
    pdfium.FPDFBitmap_GetStride.restype = ctypes.c_int
    pdfium.FPDF_RenderPageBitmap.argtypes = [handle, handle, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int]
    pdfium.FPDFBitmap_Destroy.argtypes = [handle]
    pdfium.FPDF_ClosePage.argtypes = [handle]
    pdfium.FPDF_CloseDocument.argtypes = [handle]

    document = pdfium.FPDF_LoadDocument(str(pdf_path).encode(), None)
    if not document:
        raise RuntimeError(f"PDFium could not load {pdf_path}")
    page = pdfium.FPDF_LoadPage(document, 0)
    width = round(pdfium.FPDF_GetPageWidthF(page) * scale)
    height = round(pdfium.FPDF_GetPageHeightF(page) * scale)
    bitmap = pdfium.FPDFBitmap_Create(width, height, 1)
    pdfium.FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF)
    pdfium.FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, 0)
    stride = pdfium.FPDFBitmap_GetStride(bitmap)
    raw = ctypes.string_at(pdfium.FPDFBitmap_GetBuffer(bitmap), stride * height)
    image = Image.frombuffer("RGBA", (width, height), raw, "raw", "BGRA", stride, 1).convert("RGB")
    pdfium.FPDFBitmap_Destroy(bitmap)
    pdfium.FPDF_ClosePage(page)
    pdfium.FPDF_CloseDocument(document)
    pdfium.FPDF_DestroyLibrary()
    return image


def main() -> None:
    if not PDF.is_file():
        raise FileNotFoundError(PDF)
    if not PDFIUM.is_file():
        raise FileNotFoundError(PDFIUM)
    image = render_page(PDF)
    full_page = OUT / "scale_label_page.png"
    image.save(full_page)
    # The renderer positions the first 58x40 mm label at 10 pt page margins.
    factor = 2.2
    margin = round(10 * factor)
    width, height = round(58 * 72 / 25.4 * factor), round(40 * 72 / 25.4 * factor)
    # RTL Wrap puts its first cell against the right page edge.
    x, y = image.width - margin - width, margin
    image.crop((x, y, x + width, y + height)).save(OUT / "scale_label_crop.png")
    print(f"Rendered {full_page} and {OUT / 'scale_label_crop.png'} ({image.width}x{image.height})")


if __name__ == "__main__":
    main()
