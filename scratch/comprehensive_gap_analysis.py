import json
import os
import re

kb_path = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\fsc_mcp_suite_v1\fsc_mcp\fsc_kb_mcp\data\knowledge_base.json'
with open(kb_path, 'r', encoding='utf-8') as f:
    kb = json.load(f)

guides = kb.get('guides', [])

def parse_id(gid_str):
    parts = str(gid_str).split('.')
    return [int(p) if p.isdigit() else p for p in parts]

sorted_guides = sorted(guides, key=lambda x: parse_id(x.get('guide_id') or x.get('id') or x.get('number')))

chapters = {}
for g in sorted_guides:
    gid = str(g.get('guide_id') or g.get('id') or g.get('number'))
    ch = gid.split('.')[0]
    if ch not in chapters:
        chapters[ch] = []
    chapters[ch].append(g)

print(f"Total Guides: {len(sorted_guides)} across {len(chapters)} chapters\n")

for ch, g_list in chapters.items():
    print(f"--- Chapter {ch} ({len(g_list)} guides) ---")
    for g in g_list:
        gid = str(g.get('guide_id') or g.get('id') or g.get('number'))
        title = g.get('title') or g.get('name')
        rules_cnt = len(g.get('rules', []))
        chk_cnt = len(g.get('checklist', []))
        print(f"  {gid:8} | Rules: {rules_cnt:2} | Checklist: {chk_cnt:2} | {title}")
