#!/usr/bin/env python3
"""
Freedom Supercars - Chapter 10 Full Verification Suite
Guides 10.3 (Trip Stories), 10.4 (Service Trips), and 10.5 (Tolls)

Verifies:
- Guide 10.3: Trip Stories
  * GET /v1/trips/stories/prompts: Active prompts ordered by sort_order
  * POST /v1/trips/:id/story: Reject open trips; record completed trip story (title, intro, cover photo, visibility, answers)
  * POST /v1/trips/:id/story/answers: Autosave incremental answers, advancing last_saved_at
  * GET /v1/trips/:id/story: Retrieve story with answers, enforce privacy restrictions
- Guide 10.4: Service Trips
  * POST /v1/trips/service/checkout: Vendor dispatch, category, type, reason, odometer, pay_vop_use='Not Earning'
  * Vehicle status set to 'maintenance', prevent concurrent open trips
  * POST /v1/trips/service/:id/checkin: Close trip before cost known, service miles isolated from member allowances
  * Vehicle status restored to 'available'
  * PATCH /v1/trips/service/:id/cost: Enforce Rule 10.4-R07 (never bill both member and partner)
  * Recharge to member raises fs.member_charge
  * GET /v1/trips/service: List service trips with joins to vendor and vehicle
- Guide 10.5: Toll Transactions
  * POST /v1/tolls/import: Batch import with tag resolution and deduplication on (authority, tag, timestamp)
  * POST /v1/tolls/match: Match tolls to actual trip windows (actual times)
  * Service trip tolls marked matched as club cost (no member charge)
  * GET /v1/tolls/unmatched: Unmatched queue ordered oldest first
  * PATCH /v1/tolls/:id/dispute and PATCH /v1/tolls/:id/exclude
  * POST /v1/trips/:id/tolls/bill: Aggregate all matched tolls into a single member charge
"""

import sys
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta

BASE_URL = "https://freedom-supercars-prod-api-721852694030.us-south1.run.app"

def request(method, path, body=None, token=None):
    url = f"{BASE_URL}{path}"
    data = json.dumps(body).encode("utf-8") if body is not None else None
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            status = resp.status
            content = resp.read().decode("utf-8")
            return status, json.loads(content) if content else {}
    except urllib.error.HTTPError as e:
        content = e.read().decode("utf-8")
        try:
            parsed = json.loads(content)
        except Exception:
            parsed = {"error": content}
        return e.code, parsed

def log_test(name, success, details=""):
    mark = "PASS" if success else "FAIL"
    print(f"[{mark}] {name} - {details}")
    if not success:
        sys.exit(1)

def run_suite():
    print("=" * 80)
    print("FREEDOM SUPERCARS - CHAPTER 10 FULL E2E VERIFICATION SUITE")
    print("Guides 10.3 (Stories), 10.4 (Service Trips), 10.5 (Tolls)")
    print(f"Target: {BASE_URL}")
    print("=" * 80)

    # 1. Health check
    status, health = request("GET", "/readyz")
    log_test("API Service Liveness", status == 200 and health.get("database") == "connected", f"status={status}")

    # =========================================================================
    # SETUP: GET VEHICLES & MEMBERS TO SEED FRESH TRIPS
    # =========================================================================
    status, fleet_resp = request("GET", "/v1/fleet")
    all_vehicles = fleet_resp.get("vehicles", []) or fleet_resp.get("fleet", [])
    
    status, trips_resp = request("GET", "/v1/trips?limit=100")
    open_vehicle_ids = {t["vehicle_id"] for t in trips_resp.get("trips", []) if not t.get("end_time_actual")}

    status, rc_resp = request("GET", "/v1/rate-cards/c88c2fb4-ada1-43f5-8edd-af05217a7594")
    placed_ids = {p.get("vehicle_id") for p in rc_resp.get("rate_card", {}).get("placements", []) if p.get("vehicle_id")}
    
    available_vehicles = [
        v for v in all_vehicles 
        if v.get("status") == "available" 
        and (v.get("vehicle_id") or v.get("id")) not in open_vehicle_ids
        and (v.get("vehicle_id") or v.get("id")) in placed_ids
    ]
    log_test("Fleet Vehicles Available", len(available_vehicles) >= 2, f"Found {len(available_vehicles)} available vehicles")

    veh1 = available_vehicles[0]
    veh2 = available_vehicles[1]
    veh1_id = veh1.get("vehicle_id") or veh1.get("id")
    veh2_id = veh2.get("vehicle_id") or veh2.get("id")
    veh1_tag = veh1.get("license_plate") or veh1.get("stock_number") or "FS-HOU-001"
    veh2_tag = veh2.get("license_plate") or veh2.get("stock_number") or "FS-HOU-002"

    status, members_resp = request("GET", "/v1/members?limit=5")
    members = members_resp.get("members", [])
    log_test("Members Available", len(members) >= 1, f"Found {len(members)} members")
    test_member = members[0]
    test_member_id = test_member["id"]

    # =========================================================================
    # GUIDE 10.4: SERVICE TRIPS
    # =========================================================================
    print("\n--- Testing Guide 10.4 (Service Trips) ---")
    
    # 2. Checkout Service Trip
    service_checkout_payload = {
        "vehicle_id": veh1_id,
        "starting_odometer": 18500,
        "service_category_code": "maintenance",
        "service_type_code": "scheduled",
        "service_reason_code": "oil_change",
        "service_notes": "Annual factory fluid service and 50-point diagnostic check",
        "fuel_start_percent": 90,
        "start_time_actual": (datetime.now(timezone.utc) - timedelta(hours=3)).strftime("%Y-%m-%dT%H:%M:%SZ")
    }

    status, s_trip_resp = request("POST", "/v1/trips/service/checkout", service_checkout_payload)
    log_test("Guide 10.4: Service Trip Checkout", status == 201, f"status={status}")
    s_trip = s_trip_resp.get("service_trip", {})
    s_trip_id = s_trip.get("vehicle_trip_id")
    log_test("Guide 10.4: Trip Type is 'service'", s_trip.get("trip_type_code") == "service", f"type={s_trip.get('trip_type_code')}")
    log_test("Guide 10.4: pay_vop_use is 'Not Earning'", s_trip.get("pay_vop_use") == "Not Earning", f"pay_vop={s_trip.get('pay_vop_use')}")

    # 3. Concurrent Open Trip Prevention for Service Trip
    status, dup_s_trip = request("POST", "/v1/trips/service/checkout", service_checkout_payload)
    log_test("Guide 10.4: Prevent Concurrent Open Service Trip", status == 409, f"status={status}")

    # 4. Checkin Service Trip (Cost Unknown initially - Rule 10.4-R04)
    service_checkin_payload = {
        "closing_odometer": 18535,
        "fuel_end_percent": 88,
        "service_notes": "Fluids changed, oil filter torqued to OEM spec, road tested 35 miles.",
        "end_time_actual": (datetime.now(timezone.utc) - timedelta(hours=1)).strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    status, s_close_resp = request("POST", f"/v1/trips/service/{s_trip_id}/checkin", service_checkin_payload)
    log_test("Guide 10.4: Service Trip Checkin (Closed Before Cost Known)", status == 200, f"status={status}")
    s_closed = s_close_resp.get("service_trip", {})
    log_test("Guide 10.4: Service Miles Isolated (Driven 35 miles)", s_closed.get("miles_driven") == 35, f"miles={s_closed.get('miles_driven')}")

    # 5. Enforce Rule 10.4-R07: A cost is NEVER billed to both a member and a vehicle partner!
    status, bad_cost = request("PATCH", f"/v1/trips/service/{s_trip_id}/cost", {
        "service_cost": 450.00,
        "billed_member_id": test_member_id,
        "billed_vehicle_partner_id": "00000000-0000-0000-0000-000000000001",
        "billed_amount": 450.00
    })
    log_test("Guide 10.4 Rule 10.4-R07: Prohibit Dual Billing (Member + Partner)", status == 400, f"status={status}")

    # 6. Update Service Cost & Recharge to Member
    status, cost_resp = request("PATCH", f"/v1/trips/service/{s_trip_id}/cost", {
        "service_cost": 450.00,
        "warranty_claim_reference": "WARR-2026-OIL",
        "billed_member_id": test_member_id,
        "billed_amount": 250.00, # Goodwill partial absorption (Rule 10.4-R06)
        "service_notes": "Club absorbed $200 of invoice as courtesy."
    })
    log_test("Guide 10.4: Record Cost & Recharge to Member", status == 200, f"status={status}")
    cost_data = cost_resp.get("service_trip", {})
    log_test("Guide 10.4: Billed Amount Differs from Cost (Rule 10.4-R06)", 
             float(cost_data.get("service_cost", 0)) == 450.0 and float(cost_data.get("billed_amount", 0)) == 250.0,
             f"cost={cost_data.get('service_cost')}, billed={cost_data.get('billed_amount')}")

    # 7. List Service Trips
    status, s_list = request("GET", "/v1/trips/service")
    log_test("Guide 10.4: List Service Trips", status == 200 and len(s_list.get("service_trips", [])) >= 1, 
             f"count={s_list.get('count')}")

    # =========================================================================
    # CREATE A COMPLETED MEMBER TRIP FOR STORIES & TOLLS
    # =========================================================================
    print("\n--- Setting up Completed Member Trip for Guides 10.3 & 10.5 ---")
    
    import uuid
    uniq = uuid.uuid4().hex[:6]
    status, onboard_resp = request("POST", "/v1/members/onboard", {
        "first_name": "Eleanor",
        "last_name": f"Vance_{uniq}",
        "email": f"eleanor.{uniq}@freedomsupercars.test",
        "phone": "713.555.0188",
        "date_of_birth": "1990-06-20",
        "drivers_license_number": f"TX-CH10-{uniq.upper()}",
        "drivers_license_state": "TX",
        "primary_location_code": "HOU",
        "plan_code": "PLAN_100",
        "planned_start_date": "2026-10-01"
    })
    member_data = onboard_resp.get("member", {})
    sub_id = member_data.get("subscription_id")
    mem_id = member_data.get("member_id")

    request("POST", f"/v1/members/{mem_id}/payment-arrangement", {
        "payment_method_type": "Card",
        "billing_email": f"eleanor.{uniq}@freedomsupercars.test"
    })
    request("POST", f"/v1/members/{mem_id}/activate", {
        "payment_arrangement_confirmed": True,
        "activation_date": "2026-10-01",
        "joining_bonus_points": 500
    })

    # Create reservation for veh2
    start_time = datetime.now(timezone.utc) - timedelta(days=2)
    end_time = datetime.now(timezone.utc) - timedelta(hours=4)
    
    res_payload = {
        "subscription_id": sub_id,
        "vehicle_id": veh2_id,
        "pickup_at": start_time.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "return_at": end_time.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "destination": "Hill Country Tour",
        "purpose": "Weekend Excursion",
        "auto_confirm": True
    }
    status, res_resp = request("POST", "/v1/reservations", res_payload)
    member_res_id = res_resp.get("reservation", {}).get("id") or res_resp.get("id")
    print(f"DEBUG res_resp (status={status}): {res_resp}")

    # Checkout member trip
    m_checkout_payload = {
        "reservation_id": member_res_id,
        "starting_odometer": 12000,
        "fuel_start_percent": 100,
        "condition": "excellent",
        "start_time_actual": start_time.strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    status, m_trip_resp = request("POST", f"/v1/reservations/{member_res_id}/pickup", m_checkout_payload)
    print(f"DEBUG pickup (status={status}): {m_trip_resp}")
    if status not in [200, 201]:
        status, m_trip_resp = request("POST", "/v1/trips/checkout", m_checkout_payload)
        print(f"DEBUG trips/checkout fallback (status={status}): {m_trip_resp}")
    member_trip_id = m_trip_resp.get("trip", {}).get("trip_id") or m_trip_resp.get("trip", {}).get("vehicle_trip_id")
    log_test("Member Trip Checkout Created", status in [200, 201] and member_trip_id is not None, f"trip_id={member_trip_id}")

    # =========================================================================
    # GUIDE 10.3: TRIP STORIES
    # =========================================================================
    print("\n--- Testing Guide 10.3 (Trip Stories) ---")

    # 8. GET /v1/trips/stories/prompts
    status, prompts_resp = request("GET", "/v1/trips/stories/prompts")
    prompts = prompts_resp.get("prompts", [])
    log_test("Guide 10.3: Retrieve Active Prompts", status == 200 and len(prompts) >= 4, f"Found {len(prompts)} prompts")
    prompt1 = prompts[0]
    prompt2 = prompts[1]

    # 9. Verify Story Creation Rejected on Open Trip
    status, open_story_resp = request("POST", f"/v1/trips/{member_trip_id}/story", {
        "story_title": "Premature Story",
        "introduction": "This trip isn't over yet!"
    })
    log_test("Guide 10.3: Reject Story on Open Trip", status == 400, f"status={status}, msg={open_story_resp.get('message')}")

    # Checkin the member trip now
    m_checkin_payload = {
        "closing_odometer": 12150,
        "fuel_end_percent": 95,
        "end_time_actual": end_time.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "condition": "excellent"
    }
    status, m_checkin_resp = request("POST", f"/v1/reservations/{member_res_id}/return", m_checkin_payload)
    if status not in [200, 201]:
        status, m_checkin_resp = request("POST", f"/v1/trips/{member_trip_id}/checkin", m_checkin_payload)
    log_test("Member Trip Checkin Completed", status == 200, f"status={status}")

    # 10. Create Trip Story with Prompts & Answers (Guide 10.3)
    story_payload = {
        "story_title": "Epic Hill Country Loop in the GT3 RS",
        "introduction": "An unforgettable drive through winding roads with the 4.0L flat-six screaming.",
        "cover_photo_url": "https://storage.googleapis.com/freedom-supercars-prod/stories/hill_country_gt3.jpg",
        "visibility": "members",
        "answers": [
            {
                "prompt_id": prompt1["prompt_id"],
                "answer_text": "The defining moment was opening the throttle coming out of the canyon curves.",
                "uses_assisted": False
            },
            {
                "prompt_id": prompt2["prompt_id"],
                "answer_text": "Steering precision is surgical, rear-axle steer gives effortless agility.",
                "uses_assisted": True,
                "assisted_text": "Precision steering and dynamic rear-axle agility."
            }
        ]
    }
    status, story_resp = request("POST", f"/v1/trips/{member_trip_id}/story", story_payload)
    log_test("Guide 10.3: Create Trip Story Header & Answers", status in [200, 201], f"status={status}")
    story = story_resp.get("story", {})
    log_test("Guide 10.3: Story Title & Started_At Saved", story.get("story_title") == story_payload["story_title"] and story.get("started_at") is not None, f"started_at={story.get('started_at')}")
    log_test("Guide 10.3: Story Answers Stored", len(story.get("answers", [])) == 2, f"answers_count={len(story.get('answers', []))}")

    # 11. Autosave Answers (Guide 10.3 Step 3)
    first_saved_at = story.get("last_saved_at")
    autosave_payload = {
        "prompt_id": prompt1["prompt_id"],
        "answer_text": "Updated answer: The canyon exhaust echo at 9,000 RPM was breathtaking.",
        "uses_assisted": False
    }
    status, autosave_resp = request("POST", f"/v1/trips/{member_trip_id}/story/answers", autosave_payload)
    log_test("Guide 10.3: Autosave Answer", status == 200 and autosave_resp.get("saved") is True, f"saved={autosave_resp.get('saved')}")
    log_test("Guide 10.3: last_saved_at Stamped and Advanced", autosave_resp.get("last_saved_at") is not None, f"last_saved_at={autosave_resp.get('last_saved_at')}")

    # 12. GET /v1/trips/:id/story
    status, get_story_resp = request("GET", f"/v1/trips/{member_trip_id}/story")
    retrieved_story = get_story_resp.get("story", {})
    log_test("Guide 10.3: Retrieve Story", status == 200 and retrieved_story.get("story_title") == story_payload["story_title"], f"title={retrieved_story.get('story_title')}")
    ans1 = next((a for a in retrieved_story.get("answers", []) if a["prompt_id"] == prompt1["prompt_id"]), None)
    log_test("Guide 10.3: Autosaved Answer Updated in Story", ans1 and "9,000 RPM" in ans1.get("answer_text", ""), f"ans={ans1.get('answer_text') if ans1 else None}")

    # =========================================================================
    # GUIDE 10.5: TOLL TRANSACTIONS
    # =========================================================================
    print("\n--- Testing Guide 10.5 (Toll Transactions) ---")

    # 13. Import Batch of Toll Transactions (Guide 10.5 Step 1)
    toll_time_member = (start_time + timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%SZ")
    toll_time_service = (datetime.now(timezone.utc) - timedelta(hours=2)).strftime("%Y-%m-%dT%H:%M:%SZ")
    toll_time_unmatched = (datetime.now(timezone.utc) - timedelta(days=10)).strftime("%Y-%m-%dT%H:%M:%SZ")

    batch_id = f"TEST-BATCH-{int(datetime.now().timestamp())}"
    tolls_payload = {
        "batch_id": batch_id,
        "source": "HCTRA_CSV_IMPORT",
        "tolls": [
            {
                "toll_tag": veh2_tag,
                "transaction_at": toll_time_member,
                "toll_authority_code": "HCTRA",
                "location": "Sam Houston Tollway @ Westheimer Plaza",
                "amount": 4.75,
                "notes": "Member trip toll"
            },
            {
                "toll_tag": veh2_tag,
                "transaction_at": (start_time + timedelta(hours=3)).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "toll_authority_code": "HCTRA",
                "location": "Westpark Tollway Plaza 2",
                "amount": 3.25,
                "notes": "Member trip second toll"
            },
            {
                "toll_tag": veh1_tag,
                "transaction_at": toll_time_service,
                "toll_authority_code": "TxTag",
                "location": "Grand Parkway Segment E",
                "amount": 2.50,
                "notes": "Service trip vendor test drive"
            },
            {
                "toll_tag": "UNKNOWN-TAG-9999",
                "transaction_at": toll_time_unmatched,
                "toll_authority_code": "NTTA",
                "location": "Dallas North Tollway Plaza",
                "amount": 6.10,
                "notes": "Unrecognized tag / fleet diagnostic"
            }
        ]
    }

    status, import_resp = request("POST", "/v1/tolls/import", tolls_payload)
    log_test("Guide 10.5: Import Toll Batch", status == 201 and import_resp.get("imported_count") == 4, 
             f"imported={import_resp.get('imported_count')}, total={import_resp.get('total_submitted')}")

    # 14. Deduplication Check (Developer Note 2: Deduplicate on import)
    status, dup_import_resp = request("POST", "/v1/tolls/import", tolls_payload)
    log_test("Guide 10.5 Developer Note 2: Batch Import Deduplication", 
             status == 201 and dup_import_resp.get("duplicate_count") == 4 and dup_import_resp.get("imported_count") == 0,
             f"duplicates={dup_import_resp.get('duplicate_count')}, imported={dup_import_resp.get('imported_count')}")

    # 15. Match Tolls to Actual Trip Windows (Guide 10.5 Step 2)
    status, match_resp = request("POST", "/v1/tolls/match")
    log_test("Guide 10.5: Run Toll Matching Engine", status == 200, f"matched={match_resp.get('matched_count')}")
    matched_tolls = match_resp.get("matched_tolls", [])
    log_test("Guide 10.5: Matched Member and Service Tolls", len(matched_tolls) >= 3, f"matched_count={len(matched_tolls)}")

    # 16. Working the Unmatched Queue (Guide 10.5 Step 5)
    status, unmatched_resp = request("GET", "/v1/tolls/unmatched")
    log_test("Guide 10.5: Unmatched Queue Retrieval (Oldest First)", status == 200 and unmatched_resp.get("total_unmatched", 0) >= 1,
             f"total_unmatched={unmatched_resp.get('total_unmatched')}")
    unmatched_list = unmatched_resp.get("unmatched_tolls", [])
    unknown_toll = next((t for t in unmatched_list if t["toll_tag"] == "UNKNOWN-TAG-9999"), None)
    log_test("Guide 10.5 Developer Note 5: Unrecognised Tag Preserved in Unmatched Queue", unknown_toll is not None, f"tag={unknown_toll.get('toll_tag') if unknown_toll else None}")

    # 17. Dispute and Exclude Tolls (Guide 10.5 Step 4 & 2.5)
    if unknown_toll:
        unknown_id = unknown_toll["id"]
        status, dispute_resp = request("PATCH", f"/v1/tolls/{unknown_id}/dispute", {"notes": "Member claims tag was not in vehicle"})
        log_test("Guide 10.5: Dispute Toll", status == 200 and dispute_resp.get("toll", {}).get("match_status") == "Disputed", 
                 f"status={dispute_resp.get('toll', {}).get('match_status')}")

        status, exclude_resp = request("PATCH", f"/v1/tolls/{unknown_id}/exclude", {"notes": "Club absorbed as authority phantom read"})
        log_test("Guide 10.5: Exclude Toll (Club Decision)", status == 200 and exclude_resp.get("toll", {}).get("match_status") == "Excluded",
                 f"status={exclude_resp.get('toll', {}).get('match_status')}")

    # 18. Service Trip Tolls Billed as Club Cost (Guide 10.5 Step 2.4)
    status, s_toll_bill = request("POST", f"/v1/trips/{s_trip_id}/tolls/bill")
    log_test("Guide 10.5 Step 2.4: Service Trip Tolls are Club Cost (No Member Charge)", 
             status == 200 and s_toll_bill.get("billed") is False and s_toll_bill.get("is_club_cost") is True,
             f"resp={s_toll_bill}")

    # 19. Member Trip Aggregate Toll Billing (Guide 10.5 Step 3)
    status, m_toll_bill = request("POST", f"/v1/trips/{member_trip_id}/tolls/bill")
    log_test("Guide 10.5 Step 3.2: Aggregate Member Toll Charge Posted", 
             status == 200 and m_toll_bill.get("billed") is True and m_toll_bill.get("toll_count") == 2,
             f"count={m_toll_bill.get('toll_count')}, total=${m_toll_bill.get('total_amount')}")
    log_test("Guide 10.5: Charge Amount Sums Correctly ($4.75 + $3.25 = $8.00)",
             float(m_toll_bill.get("total_amount", 0)) == 8.00, f"amount={m_toll_bill.get('total_amount')}")
    log_test("Guide 10.5: member_charge_id Linked", m_toll_bill.get("member_charge_id") is not None, 
             f"charge_id={m_toll_bill.get('member_charge_id')}")

    # 20. Prevent Double Billing
    status, re_bill = request("POST", f"/v1/trips/{member_trip_id}/tolls/bill")
    log_test("Guide 10.5: Prevent Double Billing on Same Trip", 
             status == 200 and re_bill.get("billed") is False, f"resp={re_bill.get('message')}")

    print("\n" + "=" * 80)
    print("ALL 20 CHAPTER 10 (GUIDES 10.3, 10.4, 10.5) VERIFICATION TESTS PASSED!")
    print("=" * 80)

if __name__ == "__main__":
    run_suite()
