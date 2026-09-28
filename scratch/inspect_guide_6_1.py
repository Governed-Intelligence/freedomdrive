import json

kb_path = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\fsc_mcp_suite_v1\fsc_mcp\fsc_kb_mcp\data\knowledge_base.json'
with open(kb_path, 'r', encoding='utf-8') as f:
    kb = json.load(f)

g = [x for x in kb.get('guides', []) if str(x.get('guide_id') or x.get('id') or x.get('number')) == '6.1'][0]

print(f"=== GUIDE 6.1: {g.get('title')} ===")
print("\n=== RULES ===")
for r in g.get('rules', []):
    print(f"R{r.get('n')}: {r.get('text')}")

print("\n=== CHECKLIST ===")
for c in g.get('checklist', []):
    print(f"{c.get('item_id')}: {c.get('text')}")
