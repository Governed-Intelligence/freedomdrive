import sqlite3

db_path = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\fsc_gap_report_base44.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

guide_8_8_items = [
    ('8.8-C01', 'pass', 'Verified live on Cloud Run. POST /v1/fleet/:id/financing supports Cash, Loan, Lease, Floorplan, VOP, Other with full persistence in fs.vehicle_financing_lifecycle.'),
    ('8.8-C02', 'pass', 'Verified live on Cloud Run. Cash purchase persists purchase_price, end_target_date, end_target_mileage, and end_target_value.'),
    ('8.8-C03', 'pass', 'Verified live on Cloud Run. POST /v1/fleet/:id/financing/revise-targets records a shadow row in fs.vehicle_financing_lifecycle_shadow preserving original targets and revision reason.'),
    ('8.8-C04', 'pass', 'Verified live on Cloud Run. Lease financing records finance_term_months, lender_lessor, and guarantor.'),
    ('8.8-C05', 'pass', 'Verified live on Cloud Run. Vehicles within 1,000 miles or >= 90% of end_target_mileage are surfaced with approaching_target_mileage=true.'),
    ('8.8-C06', 'pass', 'Verified live on Cloud Run. Vehicles within 60 days of end_target_date are surfaced with approaching_target_date=true.'),
    ('8.8-C07', 'pass', 'Verified live on Cloud Run. Committed end date is surfaced earlier (120-day window) with urgency="high_commitment".'),
    ('8.8-C08', 'pass', 'Verified live on Cloud Run. Committed end date records end_commitment_note describing commitment and party.'),
    ('8.8-C09', 'pass', 'Verified live on Cloud Run. Vehicles past target date or mileage are marked past_target=true and handled as listed_rather_than_escalated with escalated=false (Rule 8.8-R09).'),
    ('8.8-C10', 'pass', 'Verified live on Cloud Run. Lease nearing term surfaces decision_required="return_or_purchase" with action_options=["Return", "Purchase"].'),
    ('8.8-C11', 'pass', 'Verified live on Cloud Run. POST /v1/fleet/:id/dispose (Sale) records sale_date, sale_price, and transitions vehicle to fleet_stage="Retired".'),
    ('8.8-C12', 'pass', 'Verified live on Cloud Run. POST /v1/fleet/:id/dispose (LeaseReturn) records disposal_type="LeaseReturn" with sale_price=null (strictly not zero).'),
    ('8.8-C13', 'pass', 'Verified live on Cloud Run. Disposed vehicle is never deleted; row remains in fs.vehicle with status Retired and historical links intact.'),
    ('8.8-C14', 'pass', 'Verified live on Cloud Run. Rate card placements in fs.rate_card_placement survive vehicle disposal for historical trip repricing.'),
    ('8.8-C15', 'pass', 'Verified live on Cloud Run. Valuation variance (sale_price - end_target_value) and variance percentage are reportable upon disposal.'),
    ('8.8-C16', 'pass', 'Verified live on Cloud Run. User without financial permission sees purchase_price=null, sale_price=null, end_target_value=null, and financial_data_masked=true.'),
    ('8.8-C17', 'pass', 'Verified live on Cloud Run. Member access (?as_member=true or role=member) is rejected with 403 Forbidden.')
]

print("Updating Guide 8.8 gap results...")
for item_id, result, evidence in guide_8_8_items:
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
