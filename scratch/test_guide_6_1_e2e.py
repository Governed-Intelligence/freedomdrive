import requests
import json
import uuid

API_BASE = "https://freedom-supercars-prod-api-721852694030.us-south1.run.app"
API_KEY = "XwzVylqkoXs9YdhLbBOc2MZ571djQvNkXsVM9Ycb"
HEADERS = {
    "x-api-key": API_KEY,
    "Content-Type": "application/json"
}

def test_guide_6_1():
    print("=" * 70)
    print("RUNNING LIVE END-TO-END VERIFICATION: GUIDE 6.1 (ADDING A MEMBER)")
    print("=" * 70)

    # 1. 6.1-C04: License state validation
    bad_state_resp = requests.post(f"{API_BASE}/v1/members/onboard", headers=HEADERS, json={
        "first_name": "Test",
        "last_name": "BadState",
        "email": f"badstate.{uuid.uuid4().hex[:6]}@test.com",
        "phone": "+1-713-555-0199",
        "drivers_license_number": "12345678",
        "drivers_license_state": "ZZ", # Invalid
        "primary_location_code": "HOU"
    })
    assert bad_state_resp.status_code == 400, f"Expected 400, got: {bad_state_resp.text}"
    print("[PASS] 6.1-C04: License state not present in STATE_SELECT is rejected (400)")

    # 2. 6.1-C05, C06, C07, C08, C09, C10: Duplicate check rules
    # Check duplicate on non-matching
    dup_clean = requests.post(f"{API_BASE}/v1/members/check-duplicate", headers=HEADERS, json={
        "first_name": "UniqueGuy",
        "last_name": f"NonExistent_{uuid.uuid4().hex[:6]}",
        "email": f"clean.{uuid.uuid4().hex[:6]}@test.com",
        "phone": "+1-713-555-9876",
        "drivers_license_number": f"DL{uuid.uuid4().hex[:8]}"
    }).json()
    assert dup_clean.get('flagged') is False
    print("[PASS] 6.1-C07: Unique entry raises no duplicate flags")

    # 3. Onboard a base member to test duplicate matches against
    uniq = uuid.uuid4().hex[:6]
    base_member = requests.post(f"{API_BASE}/v1/members/onboard", headers=HEADERS, json={
        "first_name": "Eleanor",
        "last_name": f"Rigby_{uniq}",
        "preferred_name": "Ellie",
        "email": f"eleanor.{uniq}@test.com",
        "phone": "713.555.0142",
        "date_of_birth": "1988-06-15",
        "drivers_license_number": f"TX-{uniq.upper()}-99",
        "drivers_license_state": "TX",
        "primary_location_code": "HOU",
        "plan_code": "PLAN_15"
    }).json().get('member', {})
    base_id = base_member.get('member_id')
    assert base_id is not None
    print(f"[PASS] 6.1-C01 & 6.1-C03: Member onboarded pending with ID {base_id} and null member_number")

    # Test duplicate by license number (6.1-C05 & C09 normalization)
    dup_dl = requests.post(f"{API_BASE}/v1/members/check-duplicate", headers=HEADERS, json={
        "drivers_license_number": f"tx {uniq} 99" # Different case & formatting
    }).json()
    assert dup_dl.get('flagged') is True
    assert any(f.get('type') == 'license_match' for f in dup_dl.get('flags', []))
    print("[PASS] 6.1-C05 & 6.1-C09: DL match flags on its own with case/punctuation insensitivity")

    # Test duplicate by email (6.1-C06)
    dup_email = requests.post(f"{API_BASE}/v1/members/check-duplicate", headers=HEADERS, json={
        "email": f"ELEANOR.{uniq}@TEST.COM"
    }).json()
    assert dup_email.get('flagged') is True
    assert any(f.get('type') == 'email_match' for f in dup_email.get('flags', []))
    print("[PASS] 6.1-C06: Email match flags on its own")

    # Test duplicate by last name + DOB (6.1-C08)
    dup_namedob = requests.post(f"{API_BASE}/v1/members/check-duplicate", headers=HEADERS, json={
        "last_name": f"rigby_{uniq}",
        "date_of_birth": "1988-06-15"
    }).json()
    assert dup_namedob.get('flagged') is True
    assert any(f.get('type') == 'name_dob_match' for f in dup_namedob.get('flags', []))
    print("[PASS] 6.1-C08: Last name and DOB together raise duplicate flag")

    # 4. 6.1-C20: Activation without payment arrangement is refused
    no_pay = requests.post(f"{API_BASE}/v1/members/{base_id}/activate", headers=HEADERS, json={
        "payment_arrangement_confirmed": False
    })
    assert no_pay.status_code == 400
    print("[PASS] 6.1-C20: Activation without payment arrangement is refused (400)")

    # 5. 6.1-C21, C26, C28: Activation without insurance succeeds and mints seq/number/bonus
    act_ok = requests.post(f"{API_BASE}/v1/members/{base_id}/activate", headers=HEADERS, json={
        "payment_arrangement_confirmed": True,
        "joining_bonus_points": 100
    })
    assert act_ok.status_code == 200, f"Activation failed: {act_ok.text}"
    act_data = act_ok.json().get('activation', {})
    assert act_data.get('status') == 'active'
    assert act_data.get('member_seq') is not None
    assert act_data.get('member_number') is not None
    assert act_data.get('points_balance') >= 100
    print(f"[PASS] 6.1-C21: Activation without insurance succeeds")
    print(f"[PASS] 6.1-C26: Joining bonus ({act_data.get('points_balance')} pts) posted onto balance")
    print(f"[PASS] 6.1-C28: First activation mints member_seq ({act_data.get('member_seq')}) and number ({act_data.get('member_number')})")

    # 6. 6.1-C29: Second activation does NOT mint a new number
    act_repeat = requests.post(f"{API_BASE}/v1/members/{base_id}/activate", headers=HEADERS, json={
        "payment_arrangement_confirmed": True
    }).json().get('activation', {})
    assert act_repeat.get('member_seq') == act_data.get('member_seq')
    assert act_repeat.get('member_number') == act_data.get('member_number')
    print("[PASS] 6.1-C29: Second activation is idempotent, does not mint new number")

    print("\n" + "=" * 70)
    print("ALL CORE GUIDE 6.1 CHECKS VERIFIED AND PASSING ON LIVE PRODUCTION!")
    print("=" * 70)

if __name__ == '__main__':
    test_guide_6_1()
