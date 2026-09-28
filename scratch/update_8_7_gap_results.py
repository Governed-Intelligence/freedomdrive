import sqlite3

db_path = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\fsc_gap_report_base44.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

guide_8_7_items = [
    ('8.7-C01', 'pass', 'Verified live on Cloud Run. POST /v1/fleet/:id/transfers/arrive opens a location row in fs.vehicle_location with effective_from=CURRENT_DATE and effective_to IS NULL.'),
    ('8.7-C02', 'pass', 'Verified live on Cloud Run. POST /v1/fleet/:id/transfers/depart closes active location row with effective_to=CURRENT_DATE.'),
    ('8.7-C03', 'pass', 'Verified live on Cloud Run. Temporary loan transfer (is_temporary_loan=true) updates location while leaving vehicle home_branch_id untouched.'),
    ('8.7-C04', 'pass', 'Verified live on Cloud Run. Permanent reassignment transfer (is_temporary_loan=false) updates both vehicle location and home_branch_id to destination.'),
    ('8.7-C05', 'pass', 'Verified live on Cloud Run. POST /v1/fleet/:id/transfers/plan creates InternalBlock reservation on calendar for travel dates.'),
    ('8.7-C06', 'pass', 'Verified live on Cloud Run. POST /v1/fleet/:id/transfers/depart requires origin departure inspection; omitting it rejects with 400 validation error (Rule 8.7-R04).'),
    ('8.7-C07', 'pass', 'Verified live on Cloud Run. POST /v1/fleet/:id/transfers/arrive returns structured comparison between departure and arrival inspections.'),
    ('8.7-C08', 'pass', 'Verified live on Cloud Run. Damage present at arrival and absent at departure automatically sets transport_damage_flag=true in fs.vehicle_inspection_transfer.'),
    ('8.7-C09', 'pass', 'Verified live on Cloud Run. Missing key count (departure keys vs arrival keys) is calculated and surfaced in comparison.'),
    ('8.7-C10', 'pass', 'Verified live on Cloud Run. Vehicle arriving from transfer transitions to condition_code=Arrived (Rule 8.7-R07).'),
    ('8.7-C11', 'pass', 'Verified live on Cloud Run. Vehicle fleet_stage remains Fleet throughout transfer departure and arrival (Rule 8.7-R08).'),
    ('8.7-C12', 'pass', 'Verified live on Cloud Run. Transfer overlapping an existing member reservation returns 409 Conflict with surfaced conflict details for decision.'),
    ('8.7-C13', 'pass', 'Verified live on Cloud Run. Vehicle in transit carries condition_code=NULL (Rule 8.7-C13).')
]

print("Updating Guide 8.7 gap results...")
for item_id, result, evidence in guide_8_7_items:
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
