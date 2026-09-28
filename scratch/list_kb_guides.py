import json

kb_path = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\fsc_mcp_suite_v1\fsc_mcp\fsc_kb_mcp\data\knowledge_base.json'
with open(kb_path, 'r', encoding='utf-8') as f:
    kb = json.load(f)

guides = kb.get('guides', [])
print(f"Total guides: {len(guides)}")
for g in guides:
    gid = g.get('guide_id') or g.get('id') or g.get('number')
    title = g.get('title')
    cl_len = len(g.get('checklist', []))
    print(f"Guide {gid}: {title} (Checklist: {cl_len})")
