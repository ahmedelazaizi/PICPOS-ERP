import os
import shutil

src = r"D:\qa\print_matrix\reports\sheets"
dst = r"D:\PICPOS-ERP\docs\plans\print_audit_reports_2026-11-03"
os.makedirs(dst, exist_ok=True)
files = [
    "party_customer_contact.png", "party_supplier_contact.png",
    "trial_balance_contact.png", "sales_contact.png",
    "ledger_contact.png", "inventory_contact.png",
    "party_customer_02.png", "trial_balance_02.png",
    "sales_03.png", "ledger_02.png", "inventory_01.png",
]
for name in files:
    shutil.copy2(os.path.join(src, name), os.path.join(dst, name))
print(f"Copied {len(files)} evidence images to {dst}")
