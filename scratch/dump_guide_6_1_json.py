import json

with open('c:/Users/admin/Documents/kimi/workspace/Freedom_SuperCars/fsc_mcp_suite_v1/fsc_mcp/fsc_kb_mcp/data/knowledge_base.json', 'r', encoding='utf-8') as f:
    kb = json.load(f)

for g in kb['guides']:
    if str(g.get('guide_id')) == '6.1':
        with open('scratch/guide_6_1_full.json', 'w', encoding='utf-8') as out:
            json.dump(g, out, indent=2, ensure_ascii=False)
        print('Dumped guide 6.1 to scratch/guide_6_1_full.json')
        break
