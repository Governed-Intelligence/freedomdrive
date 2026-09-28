import requests
import json
import random
from datetime import datetime, timezone, timedelta

API_BASE = "https://freedom-supercars-prod-api-721852694030.us-south1.run.app"

def generate_random_vin():
    chars = "ABCDEFGHJKLMNPRSTUVWXYZ0123456789"
    return "".join(random.choice(chars) for _ in range(17))

def test_guide_8_7():
    print("=================================================================")
    print("VERIFYING GUIDE 8.7: Vehicle Location and Transfers (End-to-End)")
    print("=================================================================")

    results = {}

    now_utc = datetime.now(timezone.utc)
    today_str = now_utc.strftime("%Y-%m-%d")
    tomorrow_str = (now_utc + timedelta(days=1)).strftime("%Y-%m-%d")
    day_after_str = (now_utc + timedelta(days=2)).strftime("%Y-%m-%d")

    # 1. Create a fresh test vehicle at Fleet stage
    vin = generate_random_vin()
    stock_num = f"FS-TST-{random.randint(1000, 9999)}"
    vname = f"Test Transfer Ferrari {stock_num}"
    print(f"Creating test vehicle: {vname} (VIN: {vin})")

    create_res = requests.post(f"{API_BASE}/v1/fleet", json={
        "vin": vin,
        "vehicle_make_code": "FERRARI",
        "model": "296 GTB",
        "vehicle_name": vname,
        "year": "2024",
        "exterior_color": "RED",
        "interior_color": "BLACK",
        "home_branch_code": "HOU",
        "fleet_stage": "Fleet",
        "condition_code": "Ready",
        "launch_date": today_str,
    })
    assert create_res.status_code == 201, f"Create vehicle failed: {create_res.text}"
    vid = create_res.json()["vehicle"]["vehicle_id"]
    initial_home_branch = create_res.json()["vehicle"]["home_branch_id"]
    print(f"Vehicle created: {vid}, home_branch_id: {initial_home_branch}")

    # Fetch branches to get DFW and HOU branch IDs
    fleet_resp = requests.get(f"{API_BASE}/v1/fleet").json()["vehicles"]
    # We can use branch code 'DFW' and 'HOU' directly or resolve them
    dest_code = "DFW"
    origin_code = "HOU"

    # Seed initial location row for vehicle at HOU if none
    # -------------------------------------------------------------------------
    # 8.7-C12: A transfer overlapping a member reservation is surfaced.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.7-C12: Transfer overlapping member reservation is surfaced ---")
    # Book a member reservation spanning tomorrow
    book_res = requests.post(f"{API_BASE}/v1/fleet/{vid}/book", json={
        "reservation_type_code": "Member",
        "start_time": f"{tomorrow_str}T09:00:00Z",
        "end_time": f"{tomorrow_str}T17:00:00Z",
        "member_podium_status": "PLATINUM",
        "is_staff": False
    })
    print(f"Member booking status: {book_res.status_code}")
    assert book_res.status_code == 201, f"Booking setup failed: {book_res.text}"

    # Plan a transfer spanning tomorrow -> should be refused with 409 and surfaced
    plan_conflict = requests.post(f"{API_BASE}/v1/fleet/{vid}/transfers/plan", json={
        "origin_branch_id": origin_code,
        "destination_branch_id": dest_code,
        "start_time": f"{tomorrow_str}T08:00:00Z",
        "end_time": f"{tomorrow_str}T18:00:00Z",
        "force": False
    })
    print(f"Plan conflict status: {plan_conflict.status_code}")
    assert plan_conflict.status_code == 409, f"Expected 409 Conflict, got {plan_conflict.status_code}: {plan_conflict.text}"
    conflict_data = plan_conflict.json()
    assert conflict_data.get("has_conflicts") == True, "Expected has_conflicts = True"
    assert len(conflict_data.get("conflicts", [])) > 0, "Expected list of overlapping reservations"
    results["8.7-C12"] = True
    print(">>> 8.7-C12 PASSED")

    # -------------------------------------------------------------------------
    # 8.7-C05: A transfer creates an internal block for the travel days.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.7-C05: Transfer creates internal block for travel days ---")
    transit_start = (now_utc + timedelta(days=10)).strftime("%Y-%m-%d")
    transit_end = (now_utc + timedelta(days=12)).strftime("%Y-%m-%d")
    plan_res = requests.post(f"{API_BASE}/v1/fleet/{vid}/transfers/plan", json={
        "origin_branch_id": origin_code,
        "destination_branch_id": dest_code,
        "start_time": f"{transit_start}T08:00:00Z",
        "end_time": f"{transit_end}T18:00:00Z",
        "notes": "Route 8.7 E2E internal block"
    })
    assert plan_res.status_code == 201, f"Plan failed: {plan_res.text}"
    plan_data = plan_res.json()
    assert plan_data.get("internal_block") is not None
    assert plan_data["internal_block"]["reservation_type_code"] == "InternalBlock"
    results["8.7-C05"] = True
    print(">>> 8.7-C05 PASSED")

    # -------------------------------------------------------------------------
    # 8.7-C06: A transfer cannot begin without a departure inspection.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.7-C06: Transfer cannot begin without departure inspection ---")
    bad_depart = requests.post(f"{API_BASE}/v1/fleet/{vid}/transfers/depart", json={
        "destination_branch_id": dest_code,
        # departure_inspection is completely omitted
    })
    print(f"Missing departure inspection response: {bad_depart.status_code}")
    assert bad_depart.status_code in (400, 422), f"Expected 400/422 validation error, got {bad_depart.status_code}"
    results["8.7-C06"] = True
    print(">>> 8.7-C06 PASSED")

    # Open an initial location row at HOU to test 8.7-C02 closing
    init_arrive = requests.post(f"{API_BASE}/v1/fleet/{vid}/transfers/arrive", json={
        "destination_branch_id": origin_code,
        "arrival_inspection": {
            "keys_count": 2,
            "exterior_damage_found_flag": False,
            "interior_damage_found_flag": False,
        },
        "is_temporary_loan": True
    })
    assert init_arrive.status_code == 200, f"Initial arrive setup failed: {init_arrive.text}"

    # -------------------------------------------------------------------------
    # 8.7-C02: Leaving closes location row with an effective end.
    # 8.7-C11: The fleet stage is unchanged throughout.
    # 8.7-C13: A vehicle in transit carries no condition.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.7-C02, 8.7-C11, 8.7-C13: Depart origin ---")
    depart_res = requests.post(f"{API_BASE}/v1/fleet/{vid}/transfers/depart", json={
        "origin_branch_id": origin_code,
        "destination_branch_id": dest_code,
        "departure_inspection": {
            "keys_count": 2,
            "fuel_level_code": "Full",
            "car_cover_included_flag": True,
            "owner_manual_included_flag": True,
            "trickle_charger_included_flag": True,
            "exterior_damage_found_flag": False,
            "interior_damage_found_flag": False,
            "wheels_tires_ok_flag": True,
            "warning_lights_flag": False,
            "mechanical_issue_flag": False,
            "inspection_notes": "Departure inspection at HOU origin: pristine condition, 2 keys"
        },
        "is_temporary_loan": True
    })
    assert depart_res.status_code == 200, f"Depart failed: {depart_res.text}"
    depart_data = depart_res.json()

    # 8.7-C02 check: closed location row has effective_to
    assert depart_data.get("closed_location") is not None
    assert depart_data["closed_location"]["effective_to"] is not None
    results["8.7-C02"] = True
    print(">>> 8.7-C02 PASSED")

    # 8.7-C11 check: fleet_stage is unchanged ('Fleet')
    assert depart_data["vehicle"]["fleet_stage"] == "Fleet"
    results["8.7-C11"] = True
    print(">>> 8.7-C11 PASSED")

    # 8.7-C13 check: vehicle in transit carries no condition (condition_code is None)
    assert depart_data["vehicle"]["condition_code"] is None
    results["8.7-C13"] = True
    print(">>> 8.7-C13 PASSED")

    # -------------------------------------------------------------------------
    # 8.7-C01: Arriving at a branch opens a location row.
    # 8.7-C03: A temporary loan leaves the home branch unchanged.
    # 8.7-C07: Arrival inspection is presented against departure inspection.
    # 8.7-C08: Damage at arrival absent at departure sets the transport damage flag.
    # 8.7-C09: A missing key is visible in the comparison.
    # 8.7-C10: The vehicle arrives at condition Arrived.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.7-C01, 8.7-C03, 8.7-C07, 8.7-C08, 8.7-C09, 8.7-C10: Arrive at destination ---")
    # Simulate arrival with 1 missing key (departed with 2, arrived with 1)
    # and new transport damage (departed with False, arrived with True)
    arrive_res = requests.post(f"{API_BASE}/v1/fleet/{vid}/transfers/arrive", json={
        "destination_branch_id": dest_code,
        "arrival_inspection": {
            "keys_count": 1, # Missing 1 key!
            "fuel_level_code": "Full",
            "car_cover_included_flag": True,
            "owner_manual_included_flag": True,
            "trickle_charger_included_flag": True,
            "exterior_damage_found_flag": True, # New damage during transit!
            "interior_damage_found_flag": False,
            "wheels_tires_ok_flag": True,
            "warning_lights_flag": False,
            "mechanical_issue_flag": False,
            "inspection_notes": "Arrived at DFW: scratch on passenger fender, only 1 key handed over"
        },
        "is_temporary_loan": True # Temporary Loan!
    })
    assert arrive_res.status_code == 200, f"Arrive failed: {arrive_res.text}"
    arrive_data = arrive_res.json()

    # 8.7-C01: opens a location row with effective_to IS NULL
    opened_loc = arrive_data.get("opened_location")
    assert opened_loc is not None
    assert opened_loc.get("effective_to") is None
    results["8.7-C01"] = True
    print(">>> 8.7-C01 PASSED")

    # 8.7-C03: Temporary loan leaves home branch unchanged
    assert arrive_data["vehicle"]["home_branch_id"] == initial_home_branch
    results["8.7-C03"] = True
    print(">>> 8.7-C03 PASSED")

    # 8.7-C07: Arrival inspection presented against departure inspection
    comp = arrive_data.get("comparison")
    assert comp is not None
    assert arrive_data.get("departure_inspection") is not None
    assert arrive_data.get("arrival_inspection") is not None
    results["8.7-C07"] = True
    print(">>> 8.7-C07 PASSED")

    # 8.7-C08: Damage present at arrival and absent at departure sets transport damage flag
    assert comp.get("transport_damage_flag") == True, "Expected transport_damage_flag = True"
    assert comp.get("new_exterior_damage") == True
    results["8.7-C08"] = True
    print(">>> 8.7-C08 PASSED")

    # 8.7-C09: Missing key visible in comparison
    assert comp.get("has_missing_keys") == True
    assert comp.get("keys_missing") == 1
    assert comp.get("keys_departure") == 2
    assert comp.get("keys_arrival") == 1
    results["8.7-C09"] = True
    print(">>> 8.7-C09 PASSED")

    # 8.7-C10: Vehicle arrives at condition Arrived
    assert arrive_data["vehicle"]["condition_code"] == "Arrived"
    results["8.7-C10"] = True
    print(">>> 8.7-C10 PASSED")

    # -------------------------------------------------------------------------
    # 8.7-C04: A permanent reassignment changes the home branch.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.7-C04: Permanent reassignment changes home branch ---")
    # First depart from DFW
    perm_depart = requests.post(f"{API_BASE}/v1/fleet/{vid}/transfers/depart", json={
        "origin_branch_id": dest_code,
        "destination_branch_id": origin_code,
        "departure_inspection": {
            "keys_count": 1,
            "exterior_damage_found_flag": True,
            "interior_damage_found_flag": False
        },
        "is_temporary_loan": False
    })
    assert perm_depart.status_code == 200

    # Arrive at HOU permanently (is_temporary_loan = False)
    perm_arrive = requests.post(f"{API_BASE}/v1/fleet/{vid}/transfers/arrive", json={
        "destination_branch_id": dest_code, # permanently reassigning to DFW
        "arrival_inspection": {
            "keys_count": 1,
            "exterior_damage_found_flag": True,
            "interior_damage_found_flag": False
        },
        "is_temporary_loan": False # Permanent reassignment!
    })
    assert perm_arrive.status_code == 200
    perm_data = perm_arrive.json()
    dest_branch_id = perm_data["opened_location"]["current_branch_id"]
    assert perm_data["vehicle"]["home_branch_id"] == dest_branch_id, f"Expected vehicle home_branch_id = {dest_branch_id}, got {perm_data['vehicle']['home_branch_id']}"
    
    # Also verify via locations endpoint
    loc_resp = requests.get(f"{API_BASE}/v1/fleet/{vid}/locations")
    assert loc_resp.status_code == 200
    cur_loc = loc_resp.json().get("current_location")
    assert cur_loc is not None
    assert cur_loc["home_branch_id"] == dest_branch_id
    assert cur_loc["current_branch_id"] == dest_branch_id
    results["8.7-C04"] = True
    print(">>> 8.7-C04 PASSED")

    print("\n=================================================================")
    print("ALL 13 GUIDE 8.7 CHECKLIST ITEMS VERIFIED SUCCESSFULLY!")
    print("=================================================================")
    for k in sorted(results.keys()):
        print(f"  {k}: PASSED")

if __name__ == "__main__":
    test_guide_8_7()
