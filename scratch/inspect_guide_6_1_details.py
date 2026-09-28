import json

kb_path = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\fsc_mcp_suite_v1\fsc_mcp\fsc_kb_mcp\data\knowledge_base.json'
with open(kb_path, 'r', encoding='utf-8') as f:
    kb = json.load(f)

g = [x for x in kb.get('guides', []) if str(x.get('guide_id') or x.get('id') or x.get('number')) == '6.1'][0]

print("=== SCHEMA OVERVIEW ===")
print(json.dumps(g.get('schema_overview', {}), indent=2))

print("\n=== DEVELOPER NOTES ===")
for d in g.get('developer_notes', []):
    print(f"D{d.get('n')}: {d.get('text')}")
