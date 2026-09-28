import os
import json
import re

base = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\8122026'

unique_pdfs = {}
for root, dirs, files in os.walk(base):
    if 'node_modules' in root or '.git' in root:
        continue
    for f in files:
        if f.lower().endswith('.pdf'):
            fp = os.path.join(root, f)
            fname = f
            sz = os.path.getsize(fp)
            if fname not in unique_pdfs:
                unique_pdfs[fname] = {'path': fp, 'size': sz, 'rel': os.path.relpath(fp, base)}

add_a = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\Addendum_A_FreedomDRIVE_Findings_Register.pdf'
if os.path.exists(add_a):
    unique_pdfs[os.path.basename(add_a)] = {'path': add_a, 'size': os.path.getsize(add_a), 'rel': 'Addendum_A_FreedomDRIVE_Findings_Register.pdf'}

print(f"Total Unique Specification PDFs: {len(unique_pdfs)}")
for k in sorted(unique_pdfs.keys()):
    v = unique_pdfs[k]
    sz_kb = v['size'] / 1024
    print(f"{sz_kb:7.1f} KB | {k}")
