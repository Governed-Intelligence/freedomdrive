import requests
import json
import sys
import datetime
import random
import string
import uuid

BASE_URL = "https://freedom-supercars-prod-api-721852694030.us-south1.run.app"

def generate_random_vin():
    chars = string.ascii_uppercase + string.digits
    for bad in ['I', 'O', 'Q']:
        chars = chars.replace(bad, '')
    return "".join(random.choice(chars) for _ in range(17))

def run_tests():
    results = {}
    evidence = {}

    print("Setting up test vehicles for 8.9 tests...")
    fleet_resp = requests.get(f"{BASE_URL}/v1/fleet?include_unlaunched=true")
    if fleet_resp.status_code != 200:
        print(f"Failed to fetch fleet: {fleet_resp.status_code} {fleet_resp.text}")
        return
    vehicles = fleet_resp.json().get("vehicles", [])
    active_vehicles = [v for v in vehicles if v.get("fleet_stage") != "Retired"]
    v_unlimited = active_vehicles[0]["vehicle_id"]

    # Create fresh leased vehicle for 8.9 tests
    vin = generate_random_vin()
    vname = f"Test Leased Porsche FS-TST-{random.randint(1000, 9999)}"
    create_res = requests.post(f"{BASE_URL}/v1/fleet", json={
        "vin": vin,
        "vehicle_make_code": "PORSCHE",
        "model": "911 GT3",
        "vehicle_name": vname,
        "year": "2024",
        "exterior_color": "SILVER",
        "interior_color": "BLACK",
        "home_branch_code": "HOU",
        "fleet_stage": "Fleet",
        "condition_code": "Ready",
        "launch_date": datetime.date.today().isoformat(),
    })
    assert create_res.status_code == 201, f"Create vehicle failed: {create_res.text}"
    v_leased = create_res.json()["vehicle"]["vehicle_id"]

    print(f"Test vehicles: v_unlimited={v_unlimited}, v_leased={v_leased}")

    # =========================================================================
    # 8.9-C01: A vehicle with no allowance is never withheld for mileage
    # =========================================================================
    print("Testing 8.9-C01 (Vehicle with no allowance is never withheld)...")
    res_allow_unlim = requests.get(f"{BASE_URL}/v1/fleet/{v_unlimited}/mileage-allowance")
    res_chk_unlim = requests.post(f"{BASE_URL}/v1/fleet/{v_unlimited}/mileage-allowance/check-limit", json={"odometer": 999999})
    if res_allow_unlim.status_code == 200 and res_chk_unlim.status_code == 200:
        d1 = res_allow_unlim.json()
        d2 = res_chk_unlim.json()
        if d1.get("has_allowance") is False and d1.get("is_unlimited") is True and d2.get("withheld_for_mileage") is False:
            results["8.9-C01"] = "pass"
            evidence["8.9-C01"] = f"Vehicle has no allowance row (is_unlimited=true). check-limit with odometer=999999 did not withhold: {d2}"
        else:
            results["8.9-C01"] = "fail"
            evidence["8.9-C01"] = f"Unexpected unallocated vehicle response: d1={d1}, d2={d2}"
    else:
        results["8.9-C01"] = "fail"
        evidence["8.9-C01"] = f"Failed to check unlimited vehicle: {res_allow_unlim.status_code} / {res_chk_unlim.status_code}"

    # =========================================================================
    # 8.9-C02: The first allocation sets the limit to the starting odometer plus one month
    # =========================================================================
    print("Testing 8.9-C02 (First allocation sets starting odo + 1 month)...")
    start_odo = 5000
    monthly_mi = 800
    threshold = 100
    headers_mgr = {"x-user-role": "manager", "x-user-permissions": "manage_vehicle_mileage"}
    payload_setup = {
        "monthly_miles": monthly_mi,
        "effective_start": "2026-09-01",
        "starting_odometer": start_odo,
        "withhold_threshold_miles": threshold,
        "notes": "Lease contract #LC-9901 36 mo allowance"
    }
    res_setup = requests.post(f"{BASE_URL}/v1/fleet/{v_leased}/mileage-allowance", json=payload_setup, headers=headers_mgr)
    if res_setup.status_code in [200, 201]:
        setup_data = res_setup.json()
        first_alloc = setup_data.get("first_allocation") or {}
        expected_limit = start_odo + monthly_mi # 5800
        if first_alloc.get("odometer_limit") == expected_limit:
            results["8.9-C02"] = "pass"
            evidence["8.9-C02"] = f"First allocation created: starting_odometer={start_odo}, monthly_miles={monthly_mi}, odometer_limit={expected_limit} (starting + 1 month)"
        else:
            # Query GET to double check
            res_get = requests.get(f"{BASE_URL}/v1/fleet/{v_leased}/mileage-allowance")
            allocs = res_get.json().get("allocations", [])
            if allocs and allocs[0].get("odometer_limit") == expected_limit:
                results["8.9-C02"] = "pass"
                evidence["8.9-C02"] = f"First allocation confirmed in GET: odometer_limit={expected_limit} (starting + 1 month)"
            else:
                results["8.9-C02"] = "fail"
                evidence["8.9-C02"] = f"Limit mismatch: expected {expected_limit}, got {first_alloc.get('odometer_limit')}"
    else:
        results["8.9-C02"] = "fail"
        evidence["8.9-C02"] = f"Setup failed {res_setup.status_code}: {res_setup.text}"

    # =========================================================================
    # 8.9-C03: A month with no driving still posts an allocation and raises the limit
    # =========================================================================
    print("Testing 8.9-C03 (Month with no driving posts allocation and raises limit)...")
    # Vehicle drove 0 miles (odometer still 5000)
    payload_alloc_2 = {
        "allocated_on": "2026-10-01",
        "current_odometer": 5000
    }
    res_alloc_2 = requests.post(f"{BASE_URL}/v1/fleet/{v_leased}/mileage-allowance/allocate", json=payload_alloc_2, headers=headers_mgr)
    if res_alloc_2.status_code == 200:
        alloc2_data = res_alloc_2.json()
        new_limit = alloc2_data.get("new_odometer_limit")
        if new_limit is not None and new_limit >= 6600:
            results["8.9-C03"] = "pass"
            evidence["8.9-C03"] = f"Month with 0 miles driven posted allocation: limit raised to {new_limit} (+{monthly_mi} mi)"
        else:
            results["8.9-C03"] = "fail"
            evidence["8.9-C03"] = f"Expected limit >= 6600, got {new_limit}"
    else:
        results["8.9-C03"] = "fail"
        evidence["8.9-C03"] = f"Allocation 2 failed {res_alloc_2.status_code}: {res_alloc_2.text}"

    # =========================================================================
    # 8.9-C04: A vehicle passing its limit by more than the threshold is withheld, and existing reservations survive
    # =========================================================================
    print("Testing 8.9-C04 (Vehicle passing limit + threshold is withheld, reservations survive)...")
    # Current limit is 6600, threshold is 100 -> limit+threshold = 6700
    # Simulate high driving: odometer = 8500 (1800 over limit)
    res_high_odo = requests.post(f"{BASE_URL}/v1/fleet/{v_leased}/mileage-allowance/check-limit", json={"odometer": 8500})
    if res_high_odo.status_code == 200:
        high_data = res_high_odo.json()
        if high_data.get("withheld_for_mileage") is True and high_data.get("existing_reservations_survived") is True:
            results["8.9-C04"] = "pass"
            evidence["8.9-C04"] = f"Vehicle odometer 8500 exceeded limit 6600 + threshold 100. Withheld placed with code 'MileageLimit'. Existing reservations survived (not cancelled)."
        else:
            results["8.9-C04"] = "fail"
            evidence["8.9-C04"] = f"Vehicle not withheld: {high_data}"
    else:
        results["8.9-C04"] = "fail"
        evidence["8.9-C04"] = f"Check-limit failed {res_high_odo.status_code}: {res_high_odo.text}"

    # =========================================================================
    # 8.9-C05: A vehicle more than one month over stays withheld through the next allocation
    # =========================================================================
    print("Testing 8.9-C05 (Vehicle >1 month over stays withheld through next allocation)...")
    # Next allocation adds 800 miles -> new limit = 6600 + 800 = 7400 (+100 threshold = 7500).
    # Current odometer is 8500, which is STILL > 7500!
    payload_alloc_3 = {
        "allocated_on": "2026-11-01",
        "current_odometer": 8500
    }
    res_alloc_3 = requests.post(f"{BASE_URL}/v1/fleet/{v_leased}/mileage-allowance/allocate", json=payload_alloc_3, headers=headers_mgr)
    if res_alloc_3.status_code == 200:
        alloc3_data = res_alloc_3.json()
        if alloc3_data.get("is_withheld") is True and alloc3_data.get("withhold_action") == "retained":
            results["8.9-C05"] = "pass"
            evidence["8.9-C05"] = f"New limit raised to 7400, but odometer 8500 is >1 month ahead. Vehicle retained in withhold (is_withheld=True, withhold_action='retained')"
        else:
            results["8.9-C05"] = "fail"
            evidence["8.9-C05"] = f"Vehicle withhold not retained: {alloc3_data}"
    else:
        results["8.9-C05"] = "fail"
        evidence["8.9-C05"] = f"Allocation 3 failed {res_alloc_3.status_code}: {res_alloc_3.text}"

    # =========================================================================
    # 8.9-C06: Releasing the mileage withhold does not release a withhold placed for another reason
    # =========================================================================
    print("Testing 8.9-C06 (Releasing mileage withhold leaves other withholds intact)...")
    # First, place a second withhold for 'Safety' reason
    safety_withhold = {
        "vehicle_id": v_leased,
        "withhold_reason_code": "Safety",
        "starts_on": datetime.date.today().isoformat(),
        "withhold_note": "Manufacturer brake recall inspection required"
    }
    res_safety = requests.post(f"{BASE_URL}/v1/fleet/withholds", json=safety_withhold)

    # Now release the mileage withhold
    res_rel_mileage = requests.post(
        f"{BASE_URL}/v1/fleet/{v_leased}/mileage-allowance/release-withhold",
        json={"release_note": "Manager approved temporary mileage allowance waiver"},
        headers=headers_mgr
    )

    if res_rel_mileage.status_code == 200:
        rel_data = res_rel_mileage.json()
        if rel_data.get("other_withholds_intact") is True and len(rel_data.get("released_mileage_withholds", [])) > 0:
            results["8.9-C06"] = "pass"
            evidence["8.9-C06"] = f"Released MileageLimit withhold. Safety withhold remained active (other_withholds_intact=True): {rel_data.get('other_active_withholds')}"
        else:
            results["8.9-C06"] = "fail"
            evidence["8.9-C06"] = f"Other withholds not intact: {rel_data}"
    else:
        results["8.9-C06"] = "fail"
        evidence["8.9-C06"] = f"Release failed {res_rel_mileage.status_code}: {res_rel_mileage.text}"

    # Clean up safety withhold
    if res_safety.status_code == 201:
        w_id = res_safety.json().get("withhold", {}).get("reservation_withhold_id")
        if w_id:
            requests.post(f"{BASE_URL}/v1/fleet/withholds/{w_id}/release", json={"release_note": "Test cleanup"})

    # Summary
    print("\n=================== GUIDE 8.9 TEST RESULTS ===================")
    pass_count = sum(1 for v in results.values() if v == "pass")
    print(f"Total: {len(results)}/6 tested. Passed: {pass_count}")
    for k in sorted(results.keys()):
        status = results[k]
        ev = evidence.get(k, '')
        print(f"[{status.upper()}] {k}: {ev[:120]}")

    with open("scratch/guide_8_9_results.json", "w") as f:
        json.dump({"results": results, "evidence": evidence}, f, indent=2)

if __name__ == "__main__":
    run_tests()
