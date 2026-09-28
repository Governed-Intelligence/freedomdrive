import sqlite3

db_path = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\fsc_gap_report_base44.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

guide_8_9_items = [
    ('8.9-C01', 'pass', 'Verified live on Cloud Run. Vehicles without a row in fs.vehicle_mileage_allowance are unlimited and check-limit never withholds them.'),
    ('8.9-C02', 'pass', 'Verified live on Cloud Run. POST /v1/fleet/:id/mileage-allowance creates first allocation setting odometer_limit = starting_odometer + monthly_miles.'),
    ('8.9-C03', 'pass', 'Verified live on Cloud Run. POST /v1/fleet/:id/mileage-allowance/allocate posts allocation and increases limit even with zero miles driven in the period.'),
    ('8.9-C04', 'pass', 'Verified live on Cloud Run. Vehicle exceeding odometer limit + threshold is automatically withheld with MileageLimit reason; existing reservations survive.'),
    ('8.9-C05', 'pass', 'Verified live on Cloud Run. Vehicle more than one month over limit stays withheld across subsequent allocations until odometer falls within limit.'),
    ('8.9-C06', 'pass', 'Verified live on Cloud Run. Releasing MileageLimit withhold via /release-withhold leaves other active withholds (e.g. Safety) completely intact.')
]

print("Updating Guide 8.9 gap results...")
for item_id, result, evidence in guide_8_9_items:
    c.execute("""
        UPDATE gap_result
           SET result = ?,
               effort_class = 'none',
               evidence = ?
         WHERE item_id = ?
    """, (result, evidence, item_id))
    print(f"Updated {item_id} -> {result}")

conn.commit()

# Print summary for Chapter 8 and overall
rows = c.execute("SELECT result, count(*) FROM gap_result GROUP BY result").fetchall()
print("\n=== OVERALL GAP DB SUMMARY ===")
for r in rows:
    print(f"{r[0]}: {r[1]}")

ch8_rows = c.execute("SELECT result, count(*) FROM gap_result WHERE chapter_no = 8 GROUP BY result").fetchall()
print("\n=== CHAPTER 8 SUMMARY ===")
for r in ch8_rows:
    print(f"{r[0]}: {r[1]}")
