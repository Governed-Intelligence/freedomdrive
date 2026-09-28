import json

with open(r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\fsc_mcp_suite_v1\fsc_mcp\fsc_kb_mcp\data\knowledge_base.json', 'r', encoding='utf-8') as f:
    kb = json.load(f)

for g in kb.get('guides', []):
    if g.get('title') in ['Vehicle Lifecycle and Financing', 'Vehicle Mileage Allowance']:
        print(f"\n=== GUIDE: {g.get('title')} ===")
        print("Rules:")
        for r in g.get('rules', []):
            print(f"  R{r.get('n')}: {r.get('text')}")
        print("Checklist:")
        for c in g.get('checklist', []):
            print(f"  {c.get('item_id')}: {c.get('text')}")
