import os
import re

base = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars'

def count_pages_fast(filepath):
    try:
        with open(filepath, 'rb') as f:
            content = f.read()
            # search for /Type /Page (case sensitive in PDF syntax)
            # count /Type /Page but not /Pages
            matches = re.findall(b'/Type\s*/Page[^s]', content)
            if matches:
                return len(matches)
            # fallback
            matches2 = re.findall(b'/Count\s+(\d+)', content)
            if matches2:
                return int(matches2[-1])
    except Exception as e:
        return None
    return None

pdf_list = [
    ('1 - Start Here', 'FreedomDRIVE - Developer Onboarding (08-12-2026).pdf'),
    ('1 - Start Here', 'FreedomDRIVE - Project Introduction (08-12-2026).pdf'),
    ('Root', 'FreedomDRIVE - Request for Qualifications (RFQ).pdf'),
    ('Root', 'FreedomDRIVE - RFQ Project Introduction.pdf'),
    ('2 - Authoritative Files', 'FreedomDRIVE - Project Brief (08-12-2026).pdf'),
    ('2 - Authoritative Files', 'FreedomDRIVE - How It Works Guide (08-12-2026).pdf'),
    ('2 - Authoritative Files', 'FreedomDRIVE - Database Schema (08-12-2026).pdf'),
    ('2 - Authoritative Files', 'FreedomDRIVE - Data Capture Forms (08-12-2026).pdf'),
    ('2 - Authoritative Files', 'FreedomDRIVE - Implementation Guides Part 1 (08-12-2026).pdf'),
    ('2 - Authoritative Files', 'FreedomDRIVE - Implementation Guides Part 2 (08-12-2026).pdf'),
    ('2 - Authoritative Files', 'FreedomDRIVE - Implementation Guides Part 3 (08-12-2026).pdf'),
    ('2 - Authoritative Files', 'FreedomDRIVE - Implementation Guides Part 4 (08-12-2026).pdf'),
    ('2 - Authoritative Files', 'FreedomDRIVE - Implementation Guides Part 5 (08-12-2026).pdf'),
    ('4 - Reference Tools', 'FreedomDRIVE - Appendix A, Glossary (08-12-2026).pdf'),
    ('4 - Reference Tools', 'FreedomDRIVE - Appendix B, Database Schema by Domain (08-12-2026).pdf'),
    ('4 - Reference Tools', 'FreedomDRIVE - Appendix C, Hierarchical Table Index (08-12-2026).pdf'),
    ('4 - Reference Tools', 'FreedomDRIVE - Appendix G, Considered Enhancements (08-12-2026).pdf'),
    ('4 - Reference Tools', 'FreedomDRIVE - Full ERD and Relationship Review (08-12-2026).pdf'),
    ('Root', 'Addendum_A_FreedomDRIVE_Findings_Register.pdf')
]

for cat, fname in pdf_list:
    found_path = None
    for r, d, files in os.walk(base):
        if fname in files and 'node_modules' not in r and '.git' not in r:
            found_path = os.path.join(r, fname)
            break
    if found_path:
        pgs = count_pages_fast(found_path)
        sz_kb = os.path.getsize(found_path) / 1024
        print(f"{cat:22} | {fname:55} | {sz_kb:7.1f} KB | {pgs} pages")
    else:
        print(f"NOT FOUND: {fname}")
