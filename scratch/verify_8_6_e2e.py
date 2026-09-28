import requests
import json
import uuid
import random
from datetime import datetime, timedelta

API_BASE = "https://freedom-supercars-prod-api-721852694030.us-south1.run.app"

def generate_random_vin():
    chars = "ABCDEFGHJKLMNPRSTUVWXYZ0123456789"
    return "".join(random.choice(chars) for _ in range(17))

def test_guide_8_6():
    print("=================================================================")
    print("VERIFYING GUIDE 8.6: Vehicle Visibility & Launch (End-to-End)")
    print("=================================================================")

    results = {}

    # 1. First, create a fresh Intake vehicle and take it through intake companions
    vin = generate_random_vin()
    stock_num = f"FS-TST-{random.randint(1000, 9999)}"
    vname = f"Test Launch Carrera {stock_num}"
    print(f"Creating test vehicle: {vname} (VIN: {vin})")

    create_res = requests.post(f"{API_BASE}/v1/fleet", json={
        "vin": vin,
        "vehicle_make_code": "PORSCHE",
        "model": "911 Carrera",
        "vehicle_name": vname,
        "year": "2024",
        "exterior_color": "BLACK",
        "interior_color": "BLACK",
        "home_branch_code": "HOU",
        "fleet_stage": "Intake",
        "condition_code": "Arrived",
        "description": {
            "body_style": "Coupe",
            "transmission": "Automatic",
            "engine": "Hybrid",
            "seats": "4",
            "doors": "2",
            "trunk_size": "Small",
            "fuel_tank_size": 17,
            "range": 400
        },
        "spec": {
            "engine_oil_brand": "Mobil 1",
            "engine_oil_spec": "0W-40",
            "gps_type": "Other",
            "gps_device_id": f"GPS-{random.randint(10000,99999)}"
        },
        "performance": {
            "horsepower": 379,
            "top_speed": 182,
            "zero_to_sixty_time": 4.0
        },
        "registration_warranty": {
            "registration_state": "TX",
            "license_plate": f"LCH{random.randint(100,999)}"
        },
        "tires": {
            "front_tire_size": "245/35R20",
            "front_tire_psi": 33,
            "front_tire_brand": "PIRELLI",
            "front_tire_model": "P Zero",
            "rear_tire_size": "305/30R21",
            "rear_tire_psi": 38,
            "rear_tire_brand": "PIRELLI",
            "rear_tire_model": "P Zero"
        },
        "accessories": {
            "manuals": True,
            "car_cover": True,
            "charger": True,
            "number_keys": "2"
        }
    })
    assert create_res.status_code == 201, f"Create vehicle failed: {create_res.text}"
    vid = create_res.json()["vehicle"]["vehicle_id"]
    print(f"Vehicle created: {vid}")

    # Stamp arrival
    arr_res = requests.post(f"{API_BASE}/v1/fleet/{vid}/arrival", json={})
    assert arr_res.status_code == 200, f"Arrival stamp failed: {arr_res.text}"

    # Rate card placement (needed for readiness)
    sample_veh = requests.get(f"{API_BASE}/v1/fleet").json()["vehicles"][0]
    st = requests.get(f"{API_BASE}/v1/fleet/{sample_veh['vehicle_id']}/staff-tier").json()
    card_id = st["source_card"]["rate_card_id"]
    tier_id = st["tier"]["vehicle_tier_id"]
    place_res = requests.post(f"{API_BASE}/v1/fleet/placements", json={
        "vehicle_id": vid,
        "rate_card_id": card_id,
        "vehicle_tier_id": tier_id
    })
    assert place_res.status_code == 201, f"Placement failed: {place_res.text}"

    # -------------------------------------------------------------------------
    # 8.6-C01 [Launch]: Readiness completing places an awaiting-launch withhold and raises a task.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C01: complete-readiness places withhold & raises task ---")
    ready_res = requests.post(f"{API_BASE}/v1/fleet/{vid}/complete-readiness")
    assert ready_res.status_code == 200, f"Complete readiness failed: {ready_res.text}"
    ready_data = ready_res.json()
    assert ready_data["vehicle"]["fleet_stage"] == "Fleet", "Expected fleet_stage = Fleet"
    assert ready_data["vehicle"]["condition_code"] == "Ready", "Expected condition_code = Ready"
    assert ready_data["withhold"]["withhold_reason_code"] == "AwaitingLaunch", "Expected AwaitingLaunch withhold"
    assert ready_data["task"]["task_type_code"] == "VEHICLE_LAUNCH", "Expected VEHICLE_LAUNCH task"
    results["8.6-C01"] = True
    print(">>> 8.6-C01 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C02 [Launch]: A vehicle at Fleet with that withhold open is invisible to members.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C02: Vehicle with AwaitingLaunch withhold is invisible to members ---")
    member_fleet = requests.get(f"{API_BASE}/v1/fleet", params={"as_member": "true"})
    assert member_fleet.status_code == 200
    member_vids = [v["vehicle_id"] for v in member_fleet.json().get("vehicles", [])]
    assert vid not in member_vids, "Vehicle with open AwaitingLaunch withhold should NOT be visible to members"
    results["8.6-C02"] = True
    print(">>> 8.6-C02 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C03 [Launch]: A vehicle at Fleet with that withhold open is bookable by staff.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C03: Vehicle with AwaitingLaunch withhold is bookable by staff ---")
    today_str = datetime.utcnow().strftime("%Y-%m-%d")
    next_week = (datetime.utcnow() + timedelta(days=7)).strftime("%Y-%m-%d")
    
    # Check bookability as staff
    staff_eval = requests.get(f"{API_BASE}/v1/fleet/{vid}/bookability", params={
        "start_date": today_str,
        "end_date": next_week,
        "is_staff": "true"
    })
    print(f"Staff bookability: status={staff_eval.status_code}, bookable={staff_eval.json().get('is_bookable')}")
    assert staff_eval.status_code == 200 and staff_eval.json().get("is_bookable") == True

    # Book as staff
    staff_booking = requests.post(f"{API_BASE}/v1/fleet/{vid}/book", json={
        "reservation_type_code": "Service",
        "start_time": f"{today_str}T09:00:00Z",
        "end_time": f"{today_str}T17:00:00Z",
        "is_staff": True,
        "notes": "Pre-launch staff checkout"
    })
    print(f"Staff booking status: {staff_booking.status_code}")
    assert staff_booking.status_code == 201
    results["8.6-C03"] = True
    print(">>> 8.6-C03 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C14 [Templates]: Applying a template copies its rows onto the vehicle.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C14: Applying template copies rows onto vehicle ---")
    create_tpl = requests.post(f"{API_BASE}/v1/fleet/release-templates", json={
        "template_name": f"Test Template {random.randint(1000, 9999)}",
        "description": "E2E Test Template",
        "rows": [
            {"sort_order": 1, "duration_days": 14, "minimum_podium_status_code": "PLATINUM", "hide_from_lower_tiers": False},
            {"sort_order": 2, "duration_days": 14, "minimum_podium_status_code": "GOLD", "hide_from_lower_tiers": False}
        ]
    })
    assert create_tpl.status_code == 201, f"Create template failed: {create_tpl.text}"
    tpl = create_tpl.json()["template"]
    tpl_id = tpl["vehicle_release_template_id"]

    apply_res = requests.post(f"{API_BASE}/v1/fleet/{vid}/apply-release-template", json={
        "template_id": tpl_id
    })
    assert apply_res.status_code == 201, f"Apply template failed: {apply_res.text}"
    veh_rows = apply_res.json().get("release_rows", [])
    assert len(veh_rows) >= 2, "Expected copied release rows on vehicle"
    results["8.6-C14"] = True
    print(">>> 8.6-C14 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C15 [Templates]: Editing the template afterwards does not change a launched vehicle.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C15: Template edit does not affect vehicle's release rows ---")
    # Edit template row 1 duration to 99 days
    edit_tpl = requests.put(f"{API_BASE}/v1/fleet/release-templates/{tpl_id}", json={
        "rows": [
            {"sort_order": 1, "duration_days": 99, "minimum_podium_status_code": "PLATINUM", "hide_from_lower_tiers": False}
        ]
    })
    assert edit_tpl.status_code == 200
    # Check vehicle's rows
    v_rows_check = requests.get(f"{API_BASE}/v1/fleet/{vid}/release-rows")
    assert v_rows_check.status_code == 200
    current_v_rows = v_rows_check.json().get("release_rows", [])
    assert current_v_rows[0]["duration_days"] == 14, "Vehicle rows should remain 14 days, isolated from template edit"
    results["8.6-C15"] = True
    print(">>> 8.6-C15 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C04 [Launch]: Completing the launch form releases the withhold and sets the launch date.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C04: Launch form releases withhold & sets launch date ---")
    launch_res = requests.post(f"{API_BASE}/v1/fleet/{vid}/launch", json={
        "launch_date": today_str,
        "notes": "Official member launch"
    })
    assert launch_res.status_code == 200, f"Launch failed: {launch_res.text}"
    launch_data = launch_res.json()
    assert launch_data["launch_date"] == today_str
    assert launch_data["withhold_released"] is not None
    assert launch_data["task_completed"] is not None
    results["8.6-C04"] = True
    print(">>> 8.6-C04 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C07 [Release rows]: A member at the row minimum can book; a member below cannot.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C07: Member at minimum can book; below cannot ---")
    tomorrow_str = (datetime.utcnow() + timedelta(days=1)).strftime("%Y-%m-%d")
    day2_str = (datetime.utcnow() + timedelta(days=2)).strftime("%Y-%m-%d")
    # Active row requires PLATINUM (window: days 0-14)
    # Silver member attempts booking tomorrow
    silver_booking = requests.post(f"{API_BASE}/v1/fleet/{vid}/book", json={
        "reservation_type_code": "Member",
        "start_time": f"{tomorrow_str}T10:00:00Z",
        "end_time": f"{tomorrow_str}T18:00:00Z",
        "member_podium_status": "SILVER",
        "is_staff": False
    })
    print(f"Silver booking status: {silver_booking.status_code} (expected 403)")
    assert silver_booking.status_code == 403, f"Silver member should be blocked from exclusive stage, got {silver_booking.status_code}: {silver_booking.text}"

    # Platinum member attempts booking on day 2
    plat_booking = requests.post(f"{API_BASE}/v1/fleet/{vid}/book", json={
        "reservation_type_code": "Member",
        "start_time": f"{day2_str}T10:00:00Z",
        "end_time": f"{day2_str}T18:00:00Z",
        "member_podium_status": "PLATINUM",
        "is_staff": False
    })
    print(f"Platinum booking status: {plat_booking.status_code} (expected 201)")
    assert plat_booking.status_code == 201, f"Platinum member at minimum status should be allowed: {plat_booking.text}"
    results["8.6-C07"] = True
    print(">>> 8.6-C07 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C08 [Release rows]: A member below the minimum can be booked in by staff.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C08: Staff booking for member below minimum succeeds ---")
    staff_on_behalf = requests.post(f"{API_BASE}/v1/fleet/{vid}/book", json={
        "reservation_type_code": "Member",
        "start_time": f"{next_week}T10:00:00Z",
        "end_time": f"{next_week}T18:00:00Z",
        "member_podium_status": "SILVER",
        "is_staff": True,
        "notes": "Staff override for Silver member during Platinum window"
    })
    print(f"Staff on behalf status: {staff_on_behalf.status_code} (expected 201)")
    assert staff_on_behalf.status_code == 201
    results["8.6-C08"] = True
    print(">>> 8.6-C08 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C09 [Release rows]: When the last row expires, every member can book.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C09: Every member can book after rows expire ---")
    # Total duration = 14 + 14 = 28 days. Day 35 is past all rows.
    expired_date = (datetime.utcnow() + timedelta(days=35)).strftime("%Y-%m-%d")
    silver_future = requests.post(f"{API_BASE}/v1/fleet/{vid}/book", json={
        "reservation_type_code": "Member",
        "start_time": f"{expired_date}T10:00:00Z",
        "end_time": f"{expired_date}T18:00:00Z",
        "member_podium_status": "SILVER",
        "is_staff": False
    })
    print(f"Silver booking after rows expire status: {silver_future.status_code} (expected 201)")
    assert silver_future.status_code == 201
    results["8.6-C09"] = True
    print(">>> 8.6-C09 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C10 [Visibility]: Member below minimum sees vehicle with date it opens to them.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C10: Member below minimum sees open date with flag clear ---")
    vis_res = requests.get(f"{API_BASE}/v1/fleet", params={"as_member": "true", "podium_status": "SILVER"})
    assert vis_res.status_code == 200
    matched = [v for v in vis_res.json().get("vehicles", []) if v["vehicle_id"] == vid]
    assert len(matched) == 1, "Vehicle should be visible when hide_from_lower_tiers is false"
    assert "available_to_tier_date" in matched[0], "Expected available_to_tier_date on vehicle"
    results["8.6-C10"] = True
    print(">>> 8.6-C10 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C11 [Visibility]: With the flag set, that member does not see the vehicle at all.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C11: Member does not see vehicle with hide_from_lower_tiers=true ---")
    # Update vehicle's row 1 to hide_from_lower_tiers = True
    requests.post(f"{API_BASE}/v1/fleet/{vid}/release-rows", json={
        "stages": [
            {"sort_order": 1, "duration_days": 14, "minimum_podium_status_code": "PLATINUM", "hide_from_lower_tiers": True},
            {"sort_order": 2, "duration_days": 14, "minimum_podium_status_code": "GOLD", "hide_from_lower_tiers": False}
        ]
    })
    vis_res_hidden = requests.get(f"{API_BASE}/v1/fleet", params={"as_member": "true", "podium_status": "SILVER"})
    assert vis_res_hidden.status_code == 200
    matched_hidden = [v for v in vis_res_hidden.json().get("vehicles", []) if v["vehicle_id"] == vid]
    assert len(matched_hidden) == 0, "Vehicle should NOT be visible to Silver member when hide_from_lower_tiers is true"
    results["8.6-C11"] = True
    print(">>> 8.6-C11 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C12 [Visibility]: Flag clear -> vehicle appears before launch as Coming Soon.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C12: Vehicle appears as Coming Soon before launch with flag clear ---")
    future_launch = (datetime.utcnow() + timedelta(days=10)).strftime("%Y-%m-%d")
    # Create vehicle with future launch date and hide_from_lower_tiers = False
    vin_c12 = generate_random_vin()
    c12_veh = requests.post(f"{API_BASE}/v1/fleet", json={
        "vin": vin_c12,
        "vehicle_make_code": "FERRARI",
        "model": "Roma",
        "vehicle_name": f"Ferrari Roma Future {vin_c12[:6]}",
        "year": "2024",
        "exterior_color": "RED",
        "interior_color": "BLACK",
        "home_branch_code": "HOU",
        "fleet_stage": "Fleet",
        "condition_code": "Ready",
        "launch_date": future_launch
    })
    vid_c12 = c12_veh.json()["vehicle"]["vehicle_id"]
    requests.post(f"{API_BASE}/v1/fleet/{vid_c12}/release-rows", json={
        "stages": [
            {"sort_order": 1, "duration_days": 14, "minimum_podium_status_code": "PLATINUM", "hide_from_lower_tiers": False}
        ]
    })
    vis_c12 = requests.get(f"{API_BASE}/v1/fleet", params={"as_member": "true"})
    matched_c12 = [v for v in vis_c12.json().get("vehicles", []) if v["vehicle_id"] == vid_c12]
    assert len(matched_c12) == 1, "Expected Coming Soon vehicle visible in fleet list"
    assert matched_c12[0].get("is_coming_soon") == True, "Expected is_coming_soon = True"
    results["8.6-C12"] = True
    print(">>> 8.6-C12 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C13 [Visibility]: Flag set -> vehicle is invisible before launch.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C13: Vehicle invisible before launch with flag set ---")
    requests.post(f"{API_BASE}/v1/fleet/{vid_c12}/release-rows", json={
        "stages": [
            {"sort_order": 1, "duration_days": 14, "minimum_podium_status_code": "PLATINUM", "hide_from_lower_tiers": True}
        ]
    })
    vis_c13 = requests.get(f"{API_BASE}/v1/fleet", params={"as_member": "true"})
    matched_c13 = [v for v in vis_c13.json().get("vehicles", []) if v["vehicle_id"] == vid_c12]
    assert len(matched_c13) == 0, "Vehicle with hide_from_lower_tiers = True should be invisible before launch"
    results["8.6-C13"] = True
    print(">>> 8.6-C13 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C05 [Launch]: A vehicle with no launch date is never visible to members.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C05: Vehicle with no launch date is never visible to members ---")
    vin_c05 = generate_random_vin()
    c05_veh = requests.post(f"{API_BASE}/v1/fleet", json={
        "vin": vin_c05,
        "vehicle_make_code": "MCLAREN",
        "model": "Artura",
        "vehicle_name": f"McLaren Artura NoLaunch {vin_c05[:6]}",
        "year": "2024",
        "exterior_color": "BLUE",
        "interior_color": "BLACK",
        "home_branch_code": "HOU",
        "fleet_stage": "Fleet",
        "condition_code": "Ready"
    })
    vid_c05 = c05_veh.json()["vehicle"]["vehicle_id"]
    vis_c05 = requests.get(f"{API_BASE}/v1/fleet", params={"as_member": "true"})
    matched_c05 = [v for v in vis_c05.json().get("vehicles", []) if v["vehicle_id"] == vid_c05]
    assert len(matched_c05) == 0, "Vehicle with no launch date must NEVER be visible to members"
    results["8.6-C05"] = True
    print(">>> 8.6-C05 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C16 [Templates]: A vehicle can launch with no template.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C16: A vehicle can launch with no template ---")
    launch_c16 = requests.post(f"{API_BASE}/v1/fleet/{vid_c05}/launch", json={
        "launch_date": today_str
    })
    assert launch_c16.status_code == 200, f"Launch with no template failed: {launch_c16.text}"
    assert launch_c16.json()["launch_date"] == today_str
    results["8.6-C16"] = True
    print(">>> 8.6-C16 PASSED")

    # -------------------------------------------------------------------------
    # 8.6-C06 [Release rows]: With no rows, every member can book from launch date.
    # -------------------------------------------------------------------------
    print("\n--- Testing 8.6-C06: With no rows, every member can book from launch date ---")
    c06_book = requests.post(f"{API_BASE}/v1/fleet/{vid_c05}/book", json={
        "reservation_type_code": "Member",
        "start_time": f"{today_str}T11:00:00Z",
        "end_time": f"{today_str}T19:00:00Z",
        "member_podium_status": "SILVER",
        "is_staff": False
    })
    print(f"Booking on vehicle with no rows: status={c06_book.status_code}")
    assert c06_book.status_code == 201, f"Booking on vehicle with no rows failed: {c06_book.text}"
    results["8.6-C06"] = True
    print(">>> 8.6-C06 PASSED")

    print("\n=================================================================")
    print("ALL 16 GUIDE 8.6 CHECKLIST ITEMS VERIFIED SUCCESSFULLY!")
    print("=================================================================")
    for k in sorted(results.keys()):
        print(f"  {k}: PASSED")

if __name__ == "__main__":
    test_guide_8_6()
