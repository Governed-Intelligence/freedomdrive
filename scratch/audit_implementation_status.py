import os
import json
import re

kb_path = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\fsc_mcp_suite_v1\fsc_mcp\fsc_kb_mcp\data\knowledge_base.json'
with open(kb_path, 'r', encoding='utf-8') as f:
    kb = json.load(f)

guides = kb.get('guides', [])

def parse_id(gid_str):
    parts = str(gid_str).split('.')
    return [int(p) if p.isdigit() else p for p in parts]

sorted_guides = sorted(guides, key=lambda x: parse_id(x.get('guide_id') or x.get('id') or x.get('number')))

# We can categorize each guide based on:
# 1. Fully Implemented & E2E Verified
# 2. Database Schema / Structural Model Implemented (Stage 2 285 tables + migrations)
# 3. Partial / In Progress
# 4. Roadmap / Backlog

# Let's inspect test files in scratch and tests
test_files = [f for f in os.listdir('scratch') if f.startswith('test_')]
print("Active Test Suites in scratch:", test_files)
