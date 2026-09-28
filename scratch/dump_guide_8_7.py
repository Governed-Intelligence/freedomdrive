import json

with open(r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\fsc_mcp_suite_v1\fsc_mcp\fsc_kb_mcp\data\knowledge_base.json', 'r', encoding='utf-8') as f:
    kb = json.load(f)

g = [x for x in kb.get('guides', []) if x.get('title') == 'Vehicle Location and Transfers'][0]

print('=== GUIDE 8.7: Vehicle Location and Transfers ===')
print('\n=== RULES ===')
for r in g.get('rules', []):
    print(f"R{r.get('n')}: {r.get('text')}")

print('\n=== DEVELOPER NOTES ===')
for d in g.get('developer_notes', []):
    print(f"D{d.get('n')}: {d.get('text')}")

print('\n=== CHECKLIST ===')
for c in g.get('checklist', []):
    print(f"{c.get('item_id')}: {c.get('text')}")
