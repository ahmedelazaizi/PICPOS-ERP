import ctypes
import glob
import os
from PIL import Image, ImageDraw

DLL = r"D:\PICPOS-ERP\build\windows\x64\pdfium-src\bin\pdfium.dll"
ROOT = r"D:\qa\print_matrix\reports"
OUT = os.path.join(ROOT, "sheets")
os.makedirs(OUT, exist_ok=True)
api = ctypes.WinDLL(DLL)
api.FPDF_InitLibrary.restype = None
api.FPDF_LoadDocument.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
api.FPDF_LoadDocument.restype = ctypes.c_void_p
api.FPDF_GetPageCount.argtypes = [ctypes.c_void_p]
api.FPDF_GetPageCount.restype = ctypes.c_int
api.FPDF_LoadPage.argtypes = [ctypes.c_void_p, ctypes.c_int]
api.FPDF_LoadPage.restype = ctypes.c_void_p
api.FPDF_GetPageWidth.argtypes = [ctypes.c_void_p]
api.FPDF_GetPageWidth.restype = ctypes.c_double
api.FPDF_GetPageHeight.argtypes = [ctypes.c_void_p]
api.FPDF_GetPageHeight.restype = ctypes.c_double
api.FPDFBitmap_Create.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int]
api.FPDFBitmap_Create.restype = ctypes.c_void_p
api.FPDFBitmap_FillRect.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_uint]
api.FPDFBitmap_GetBuffer.argtypes = [ctypes.c_void_p]
api.FPDFBitmap_GetBuffer.restype = ctypes.POINTER(ctypes.c_ubyte)
api.FPDFBitmap_GetStride.argtypes = [ctypes.c_void_p]
api.FPDFBitmap_GetStride.restype = ctypes.c_int
api.FPDF_RenderPageBitmap.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int]
api.FPDFBitmap_Destroy.argtypes = [ctypes.c_void_p]
api.FPDF_ClosePage.argtypes = [ctypes.c_void_p]
api.FPDF_CloseDocument.argtypes = [ctypes.c_void_p]
api.FPDF_DestroyLibrary.restype = None
api.FPDF_InitLibrary()

def render(path, page_index, target_w=420):
    doc = api.FPDF_LoadDocument(os.fsencode(path), None)
    if not doc:
        raise RuntimeError(f"FPDF_LoadDocument failed: {path}")
    try:
        page = api.FPDF_LoadPage(doc, page_index)
        if not page:
            raise RuntimeError(f"FPDF_LoadPage failed: {path} page {page_index}")
        try:
            wpt, hpt = api.FPDF_GetPageWidth(page), api.FPDF_GetPageHeight(page)
            w = target_w
            h = max(1, round(target_w * hpt / wpt))
            bmp = api.FPDFBitmap_Create(w, h, 1)
            try:
                api.FPDFBitmap_FillRect(bmp, 0, 0, w, h, 0xFFFFFFFF)
                api.FPDF_RenderPageBitmap(bmp, page, 0, 0, w, h, 0, 0)
                stride = api.FPDFBitmap_GetStride(bmp)
                raw = ctypes.string_at(api.FPDFBitmap_GetBuffer(bmp), stride * h)
                return Image.frombuffer("RGBA", (w, h), raw, "raw", "BGRA", stride, 1).convert("RGB")
            finally:
                api.FPDFBitmap_Destroy(bmp)
        finally:
            api.FPDF_ClosePage(page)
    finally:
        api.FPDF_CloseDocument(doc)

pdfs = glob.glob(os.path.join(ROOT, "*", "*.pdf"))
for category in sorted({os.path.basename(os.path.dirname(p)) for p in pdfs}):
    paths = sorted(glob.glob(os.path.join(ROOT, category, "*.pdf")))
    cells = []
    for path in paths:
        doc = api.FPDF_LoadDocument(os.fsencode(path), None)
        if not doc:
            continue
        count = api.FPDF_GetPageCount(doc)
        api.FPDF_CloseDocument(doc)
        selected = sorted(set([0, 1, 2, count - 1]) & set(range(count)))
        for ix in selected:
            image = render(path, ix)
            cells.append((f"{os.path.basename(path)} · p{ix+1}/{count}", image))
    if not cells:
        continue
    cell_w, label_h, pad = 440, 24, 12
    cell_h = max(im.height for _, im in cells) + label_h
    cols = min(4, len(cells))
    rows = (len(cells) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (cell_w + pad) + pad, rows * (cell_h + pad) + pad), "#dce2e8")
    draw = ImageDraw.Draw(sheet)
    for i, (label, im) in enumerate(cells):
        x = pad + (i % cols) * (cell_w + pad)
        y = pad + (i // cols) * (cell_h + pad)
        draw.text((x, y), label, fill="#101820")
        sheet.paste(im, (x, y + label_h))
    sheet.save(os.path.join(OUT, f"{category}_contact.png"))
    # Preserve each selected page as an individual evidence image too.
    for i, (label, im) in enumerate(cells):
        im.save(os.path.join(OUT, f"{category}_{i+1:02d}.png"))
api.FPDF_DestroyLibrary()
print(f"Rendered {len(pdfs)} PDFs into {OUT}")
