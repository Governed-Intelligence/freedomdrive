import json

with open('c:/Users/admin/Documents/kimi/workspace/Freedom_SuperCars/fsc_mcp_suite_v1/fsc_mcp/fsc_kb_mcp/data/knowledge_base.json', 'r', encoding='utf-8') as f:
    kb = json.load(f)

for g in kb['guides']:
    if str(g.get('guide_id')) == '6.1':
        print('=== GUIDE 6.1 ===')
        print('Title:', g.get('title'))
        print('Tables referenced:', g.get('tables_referenced'))
        print('\n--- RULES ---')
        for r in g.get('rules', []):
            print(f"{r.get('rule_id')}: {r.get('text')}")
        print('\n--- CHECKLIST ---')
        for c in g.get('checklist', []):
            print(f"{c.get('item_id')} [{c.get('group')}]: {c.get('text')}")
        print('\n--- SECTIONS ---')
        for s in g.get('sections', []):
            print('--- Heading:', s.get('title') or s.get('heading'))
            print('Content:\n', s.get('content') or s.get('text'))
        print('\n--- DEVELOPER NOTES ---')
        print(g.get('developer_notes'))
        print('\n--- EDGE CASES ---')
        print(g.get('edge_cases'))
        break
