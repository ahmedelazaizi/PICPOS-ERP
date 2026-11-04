"""Render selected audit PDFs with the repository's pdfium.dll and build sheets."""
from __future__ import annotations

import ctypes
import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(r"D:\qa\print_fix_F\invoices")
BASELINE_ROOT = Path(r"D:\qa\print_fix_D\invoices")
PDFIUM = Path(r"D:\PICPOS-ERP\build\windows\x64\pdfium-src\bin\pdfium.dll")
SHEET_DIR = ROOT / "sheets"
COPIES = Path(r"D:\PICPOS-ERP\docs\plans\print_fix_F_2026-11-03")
SIZES = ["58mm", "78mm", "80mm", "A5", "A4"]
SCENARIOS = ["S1_5_items", "S2_15_items", "S3_25_items", "S4_42_items",
             "S5_120_items", "S6_long_name_96", "S7_no_customer_notes_discount",
             "S8_negative_return", "S9_eight_digit_discount_tax",
             "S10_split_payment_delivery", "S11_ar_en_logo_qr", "S12_zero_items", "S12_one_item", "S13_ten_digit_amount"]

pdfium = ctypes.CDLL(str(PDFIUM))
H = ctypes.c_void_p
pdfium.FPDF_InitLibrary.restype = None
pdfium.FPDF_LoadDocument.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
pdfium.FPDF_LoadDocument.restype = H
pdfium.FPDF_GetPageCount.argtypes = [H]
pdfium.FPDF_GetPageCount.restype = ctypes.c_int
pdfium.FPDF_LoadPage.argtypes = [H, ctypes.c_int]
pdfium.FPDF_LoadPage.restype = H
pdfium.FPDF_GetPageWidthF.argtypes = [H]
pdfium.FPDF_GetPageWidthF.restype = ctypes.c_float
pdfium.FPDF_GetPageHeightF.argtypes = [H]
pdfium.FPDF_GetPageHeightF.restype = ctypes.c_float
pdfium.FPDFBitmap_Create.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int]
pdfium.FPDFBitmap_Create.restype = H
pdfium.FPDFBitmap_FillRect.argtypes = [H, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_uint]
pdfium.FPDFBitmap_GetBuffer.argtypes = [H]
pdfium.FPDFBitmap_GetBuffer.restype = ctypes.POINTER(ctypes.c_ubyte)
pdfium.FPDFBitmap_GetStride.argtypes = [H]
pdfium.FPDFBitmap_GetStride.restype = ctypes.c_int
pdfium.FPDF_RenderPageBitmap.argtypes = [H, H, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int]
pdfium.FPDFBitmap_Destroy.argtypes = [H]
pdfium.FPDF_ClosePage.argtypes = [H]
pdfium.FPDF_CloseDocument.argtypes = [H]
pdfium.FPDF_DestroyLibrary.restype = None


def render(pdf: Path, out: Path, page_index: int = 0) -> Image.Image:
    doc = pdfium.FPDF_LoadDocument(str(pdf).encode(), None)
    if not doc:
        raise RuntimeError(f"FPDF_LoadDocument failed: {pdf}")
    try:
        pages = pdfium.FPDF_GetPageCount(doc)
        page_index = pages - 1 if page_index < 0 else min(max(page_index, 0), pages - 1)
        page = pdfium.FPDF_LoadPage(doc, page_index)
        if not page:
            raise RuntimeError(f"FPDF_LoadPage failed: {pdf} page {page_index}")
        try:
            scale = 1.6
            width = max(1, round(pdfium.FPDF_GetPageWidthF(page) * scale))
            height = max(1, round(pdfium.FPDF_GetPageHeightF(page) * scale))
            bitmap = pdfium.FPDFBitmap_Create(width, height, 1)
            if not bitmap:
                raise RuntimeError("FPDFBitmap_Create failed")
            try:
                pdfium.FPDFBitmap_FillRect(bitmap, 0, 0, width, height, 0xFFFFFFFF)
                pdfium.FPDF_RenderPageBitmap(bitmap, page, 0, 0, width, height, 0, 0)
                stride = pdfium.FPDFBitmap_GetStride(bitmap)
                buffer = pdfium.FPDFBitmap_GetBuffer(bitmap)
                raw = ctypes.string_at(buffer, stride * height)
                im = Image.frombuffer("RGBA", (width, height), raw, "raw", "BGRA", stride, 1).convert("RGB")
                out.parent.mkdir(parents=True, exist_ok=True)
                im.save(out)
                return im
            finally:
                pdfium.FPDFBitmap_Destroy(bitmap)
        finally:
            pdfium.FPDF_ClosePage(page)
    finally:
        pdfium.FPDF_CloseDocument(doc)


def main() -> None:
    if not PDFIUM.is_file():
        raise FileNotFoundError(f"PDFium DLL missing: {PDFIUM}")
    SHEET_DIR.mkdir(parents=True, exist_ok=True)
    COPIES.mkdir(parents=True, exist_ok=True)
    pdfium.FPDF_InitLibrary()
    try:
        tile_w, tile_h, label_h = 190, 270, 30
        sheet = Image.new("RGB", (tile_w * len(SCENARIOS), (tile_h + label_h) * len(SIZES)), "#e9edf2")
        draw = ImageDraw.Draw(sheet)
        rendered = {}
        for row, size in enumerate(SIZES):
            for col, scenario in enumerate(SCENARIOS):
                choices = sorted((ROOT / size).glob(f"*/{scenario}.pdf")) if (ROOT / size).exists() else []
                x, y = col * tile_w, row * (tile_h + label_h)
                draw.text((x + 3, y + 3), f"{size} | {scenario}", fill="#172033")
                if not choices:
                    draw.rectangle((x + 2, y + label_h, x + tile_w - 2, y + label_h + tile_h), fill="#d7dce3")
                    draw.text((x + 8, y + label_h + 10), "No template", fill="#4d596b")
                    continue
                source = choices[0]
                image_path = SHEET_DIR / f"{size}_{scenario}.png"
                image = render(source, image_path)
                image.thumbnail((tile_w - 8, tile_h - 8))
                sheet.paste(image, (x + (tile_w - image.width) // 2, y + label_h + (tile_h - image.height) // 2))
                rendered[(size, scenario)] = image_path
        sheet_path = SHEET_DIR / "invoice_matrix_contact_sheet.png"
        sheet.save(sheet_path)
        shutil.copy2(sheet_path, COPIES / "invoice_matrix_contact_sheet.png")
        selected = [("A4", "S5_120_items"), ("80mm", "S5_120_items"),
                    ("58mm", "S1_5_items"), ("58mm", "S3_25_items"),
                    ("58mm", "S5_120_items"), ("58mm", "S6_long_name_96"),
                    ("58mm", "S9_eight_digit_discount_tax"),
                    ("58mm", "S13_ten_digit_amount"),
                    ("A5", "S4_42_items"), ("80mm", "S11_ar_en_logo_qr")]
        for size, scenario in selected:
            src = rendered.get((size, scenario))
            if src:
                shutil.copy2(src, COPIES / f"{size}_{scenario}.png")

        # Render each new template directly rather than whichever alphabetically
        # first template happens to represent its paper size in the contact sheet.
        new_templates = [
            ("58mm", "thermal58_sales_return"),
            ("58mm", "thermal58_kitchen"),
            ("58mm", "thermal58_shift_closing"),
            ("58mm", "thermal58_purchase_invoice"),
            ("A5", "a5_sales_return"),
            ("A5", "a5_purchase_invoice"),
            ("80mm", "thermal80_sales_return"),
            ("80mm", "thermal80_quick_sale"),
            ("80mm", "thermal_classic"),
            ("80mm", "thermal_comprehensive"),
            ("80mm", "thermal_modern"),
            ("80mm", "kitchen_professional"),
        ]
        new_scenarios = ["S1_5_items", "S3_25_items", "S5_120_items",
                         "S6_long_name_96", "S9_eight_digit_discount_tax"]
        for size, template in new_templates:
            for scenario in new_scenarios:
                source = ROOT / size / template / f"{scenario}.pdf"
                if size == "80mm" and template == "thermal80_sales_return":
                    before_source = BASELINE_ROOT / size / template / f"{scenario}.pdf"
                    if before_source.is_file():
                        before_target = SHEET_DIR / f"{template}_{scenario}_before.png"
                        render(before_source, before_target)
                        shutil.copy2(before_target, COPIES / before_target.name)
                if source.is_file():
                    target = SHEET_DIR / f"{template}_{scenario}.png"
                    image = render(source, target)
                    shutil.copy2(target, COPIES / target.name)
                    if scenario == "S5_120_items":
                        image.thumbnail((image.width, 6000))
                        overview = COPIES / f"{template}_{scenario}_overview.png"
                        image.save(overview)
                        if size == "A5":
                            last_page = SHEET_DIR / f"{template}_{scenario}_last_page.png"
                            render(source, last_page, -1)
                            shutil.copy2(last_page, COPIES / last_page.name)
        new_sheet = Image.new("RGB", (len(new_scenarios) * 240, len(new_templates) * 330), "#e9edf2")
        new_draw = ImageDraw.Draw(new_sheet)
        for row, (_, template) in enumerate(new_templates):
            for col, scenario in enumerate(new_scenarios):
                image_path = SHEET_DIR / f"{template}_{scenario}.png"
                x, y = col * 240, row * 330
                new_draw.text((x + 4, y + 3), f"{template} | {scenario}", fill="#172033")
                if image_path.is_file():
                    with Image.open(image_path) as image:
                        image.thumbnail((228, 294))
                        new_sheet.paste(image, (x + (240 - image.width) // 2, y + 30))
        new_sheet_path = SHEET_DIR / "new_templates_contact_sheet.png"
        new_sheet.save(new_sheet_path)
        shutil.copy2(new_sheet_path, COPIES / new_sheet_path.name)

        long_receipt = rendered.get(("58mm", "S5_120_items"))
        if long_receipt:
            with Image.open(long_receipt) as overview:
                overview.thumbnail((overview.width, 6000))
                overview.save(COPIES / "58mm_S5_120_items_overview.png")
        previous_long_receipt = COPIES / "58mm_S5_120_items_before_adaptive.png"
        if previous_long_receipt.is_file():
            with Image.open(previous_long_receipt) as overview:
                overview.thumbnail((overview.width, 6000))
                overview.save(COPIES / "58mm_S5_120_items_before_adaptive_overview.png")
        previous_58mm = Path(
            r"D:\PICPOS-ERP\docs\plans\print_audit_2026-11-03\58mm_S9_eight_digit_discount_tax.png"
        )
        if previous_58mm.is_file():
            shutil.copy2(previous_58mm, COPIES / "58mm_S9_before.png")
        a4_choices = sorted((ROOT / "A4").glob("*/S5_120_items.pdf"))
        if a4_choices:
            last_page = SHEET_DIR / "A4_S5_120_items_last_page.png"
            render(a4_choices[0], last_page, -1)
            shutil.copy2(last_page, COPIES / "A4_S5_120_items_last_page.png")
        print(f"PDFium rendered {len(rendered)} contact-sheet tiles")
        print(f"Contact sheet: {sheet_path}")
        print(f"Curated images: {len(list(COPIES.glob('*.png')))}")
    finally:
        pdfium.FPDF_DestroyLibrary()

if __name__ == "__main__":
    main()
