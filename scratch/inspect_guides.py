import json

kb_path = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\fsc_mcp_suite_v1\fsc_mcp\fsc_kb_mcp\data\knowledge_base.json'
with open(kb_path, 'r', encoding='utf-8') as f:
    kb = json.load(f)

for gid in ['9.2', '7.6', '7.7']:
    matching = [x for x in kb.get('guides', []) if str(x.get('guide_id') or x.get('id') or x.get('number')) == gid]
    if matching:
        g = matching[0]
        print('='*80)
        print(f"GUIDE {gid}: {g.get('title')}")
        print('='*80)
        print("TABLES:", g.get('tables', []))
        print("\nSCHEMA OVERVIEW:\n", g.get('schema_overview'))
        print("\nDEVELOPER NOTES:\n", g.get('developer_notes'))
        print("\nRULES:")
        for r in g.get('rules', []):
            print(f"  R{r.get('n')}: {r.get('text')}")
        print("\nCHECKLIST:")
        for c in g.get('checklist', []):
            print(f"  {c.get('item_id')}: {c.get('text')}")
        
        # save full json to scratch for deep inspection
        with open(f"scratch/guide_{gid.replace('.', '_')}_full.json", 'w', encoding='utf-8') as out:
            json.dump(g, out, indent=2)
