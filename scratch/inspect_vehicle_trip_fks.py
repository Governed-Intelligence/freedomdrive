import re

with open('api/db/migrations/003_stage2_complete_285_tables.sql', 'r', encoding='utf-8') as f:
    sql = f.read()

pattern = r'ALTER TABLE fs\.vehicle_trip\s+ADD CONSTRAINT\s+([a-zA-Z0-9_]+)\s+FOREIGN KEY\s*\((.*?)\)\s+REFERENCES fs\.([a-zA-Z0-9_\"]+)\s*\((.*?)\)'
matches = re.findall(pattern, sql, re.IGNORECASE)
for m in matches:
    print(f"FK {m[0]}: ({m[1]}) -> fs.{m[2]}({m[3]})")
