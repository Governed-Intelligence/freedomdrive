import sqlite3

db_path = r'c:\Users\admin\Documents\kimi\workspace\Freedom_SuperCars\fsc_gap_report_base44.db'
conn = sqlite3.connect(db_path)
c = conn.cursor()

guide_8_6_items = [
    ('8.6-C01', 'pass', 'Verified live on Cloud Run. POST /v1/fleet/:id/complete-readiness sets condition_code=Ready, places AwaitingLaunch withhold, and raises VEHICLE_LAUNCH task in fs.task.'),
    ('8.6-C02', 'pass', 'Verified live on Cloud Run. GET /v1/fleet?as_member=true excludes vehicles with open AwaitingLaunch withhold.'),
    ('8.6-C03', 'pass', 'Verified live on Cloud Run. Staff evaluateVehicleBookability and booking bypasses AwaitingLaunch withhold; member booking refused.'),
    ('8.6-C04', 'pass', 'Verified live on Cloud Run. POST /v1/fleet/:id/launch sets launch_date, releases AwaitingLaunch withhold, and marks VEHICLE_LAUNCH task COMPLETED.'),
    ('8.6-C05', 'pass', 'Verified live on Cloud Run. GET /v1/fleet?as_member=true strictly filters out any vehicle with launch_date IS NULL.'),
    ('8.6-C06', 'pass', 'Verified live on Cloud Run. Launched vehicle with no release rows permits direct booking by all members from launch_date.'),
    ('8.6-C07', 'pass', 'Verified live on Cloud Run. Exclusive stage requires minimum status PLATINUM; Silver member rejected with 403 EXCLUSIVE_STAGE_BLOCKED, Platinum member succeeds (201).'),
    ('8.6-C08', 'pass', 'Verified live on Cloud Run. Staff member with is_staff=true successfully books on behalf of Silver member during exclusive stage (201).'),
    ('8.6-C09', 'pass', 'Verified live on Cloud Run. Once cumulative duration of all release stages expires, Silver member can book directly without restriction (201).'),
    ('8.6-C10', 'pass', 'Verified live on Cloud Run. When hide_from_lower_tiers=false, member below minimum sees vehicle decorated with available_to_tier_date.'),
    ('8.6-C11', 'pass', 'Verified live on Cloud Run. When hide_from_lower_tiers=true, member below minimum is completely filtered out of GET /v1/fleet.'),
    ('8.6-C12', 'pass', 'Verified live on Cloud Run. Prior to launch date, vehicle with hide_from_lower_tiers=false appears in member list marked Coming Soon (is_coming_soon=true).'),
    ('8.6-C13', 'pass', 'Verified live on Cloud Run. Prior to launch date, vehicle with hide_from_lower_tiers=true is completely invisible to members.'),
    ('8.6-C14', 'pass', 'Verified live on Cloud Run. POST /v1/fleet/:id/apply-release-template copies template rows into fs.vehicle_release_row for that vehicle.'),
    ('8.6-C15', 'pass', 'Verified live on Cloud Run. PUT /v1/fleet/release-templates/:id updates template rows while vehicle release rows remain completely isolated and unchanged.'),
    ('8.6-C16', 'pass', 'Verified live on Cloud Run. Vehicle with 0 release rows successfully launches and operates in full open member access mode.')
]

print("Updating Guide 8.6 gap results...")
for item_id, result, evidence in guide_8_6_items:
    c.execute("""
        UPDATE gap_result
           SET result = ?,
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

ch8_rows = c.execute("SELECT result, count(*) FROM gap_result WHERE guide_id LIKE '8.%' GROUP BY result").fetchall()
print("\n=== CHAPTER 8 SUMMARY ===")
for r in ch8_rows:
    print(f"{r[0]}: {r[1]}")

conn.close()
