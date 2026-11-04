import os
import shutil
src = r"D:\qa\print_matrix\reports\sheets"
dst = r"D:\PICPOS-ERP\docs\plans\print_audit_reports_2026-11-03"
for name in ["legacy_sales_contact.png", "income_statement_contact.png", "balance_sheet_contact.png"]:
    shutil.copy2(os.path.join(src, name), os.path.join(dst, name))
print("Copied 3 additional evidence sheets (14 total planned evidence files).")
