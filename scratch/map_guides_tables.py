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

table_to_guides = {}
guide_to_tables = {}

for g in sorted_guides:
    gid = str(g.get('guide_id') or g.get('id') or g.get('number'))
    tables = g.get('tables', [])
    guide_to_tables[gid] = tables
    for t in tables:
        t_clean = t.replace('fs.', '').strip()
        table_to_guides.setdefault(t_clean, []).append(gid)

print(f"Total mapped tables in KB guides: {len(table_to_guides)}")
