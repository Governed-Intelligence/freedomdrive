import json

kb_path = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\fsc_mcp_suite_v1\fsc_mcp\fsc_kb_mcp\data\knowledge_base.json'
with open(kb_path, 'r', encoding='utf-8') as f:
    kb = json.load(f)

ch10_guides = [g for g in kb.get('guides', []) if str(g.get('guide_id') or g.get('id') or g.get('number')).startswith('10.')]

for g in sorted(ch10_guides, key=lambda x: float(str(x.get('guide_id') or x.get('id') or x.get('number')))):
    gid = str(g.get('guide_id') or g.get('id') or g.get('number'))
    title = g.get('title') or g.get('name')
    print('='*80)
    print(f'GUIDE {gid}: {title}')
    print('='*80)
    print('TABLES:', g.get('tables', []))
    print('\nSCHEMA OVERVIEW:\n', g.get('schema_overview'))
    print('\nRULES:')
    for r in g.get('rules', []):
        print(f"  R{r.get('n')}: {r.get('text')}")
    print('\nCHECKLIST:')
    for c in g.get('checklist', []):
        print(f"  {c.get('item_id')}: {c.get('text')}")
    
    with open(f'scratch/guide_{gid.replace(".", "_")}_full.json', 'w', encoding='utf-8') as out:
        json.dump(g, out, indent=2)
