import re

with open('api/db/migrations/003_stage2_complete_285_tables.sql', 'r', encoding='utf-8') as f:
    sql = f.read()

pattern = r'CREATE TABLE\s+(?:IF NOT EXISTS\s+)?([a-zA-Z0-9_\.]+)\s*\((.*?)\);'
matches = re.findall(pattern, sql, re.DOTALL | re.IGNORECASE)

print(f"Total tables found: {len(matches)}")
target_tables = {}
for name, body in matches:
    clean_name = name.replace('fs.', '').replace('"', '').strip()
    if any(k in clean_name.lower() for k in ['trip', 'odometer', 'fuel']):
        target_tables[clean_name] = body

for name, body in target_tables.items():
    print('='*80)
    print(f"TABLE: {name}")
    print('='*80)
    # print columns
    cols = [line.strip() for line in body.split('\n') if line.strip() and not line.strip().startswith('--')]
    for col in cols[:25]:
        print(' ', col)
    if len(cols) > 25:
        print(f"  ... and {len(cols) - 25} more lines")
