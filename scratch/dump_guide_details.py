import json

for gid in ["9_2", "7_6", "7_7"]:
    with open(f"scratch/guide_{gid}_full.json", "r", encoding="utf-8") as f:
        g = json.load(f)
    print("="*70)
    print(f"GUIDE {g.get('guide_id') or gid}: {g.get('title')}")
    print("="*70)
    print("RULES:")
    for r in g.get("rules", []):
        print(f"  R{r.get('n')}: {r.get('text')}")
    print("\nCHECKLIST:")
    for c in g.get("checklist", []):
        print(f"  {c.get('item_id')}: {c.get('text')}")
    print("\nDEVELOPER NOTES:")
    for n in g.get("developer_notes", []):
        print(f"  Note {n.get('n')}: {n.get('text')}")
    print("\n")
