import requests
import json
import uuid
from datetime import datetime, date

API_BASE = "https://freedom-supercars-prod-api-721852694030.us-south1.run.app"
API_KEY = "XwzVylqkoXs9YdhLbBOc2MZ571djQvNkXsVM9Ycb"
HEADERS = {
    "x-api-key": API_KEY,
    "Content-Type": "application/json"
}

def run_tests():
    print("=" * 80)
    print("RUNNING LIVE END-TO-END VERIFICATION: GUIDE 6.1 PAYMENT SCHEDULE & DUES")
    print("=" * 80)

    # 1. Verify GET /v1/subscriptions/plans returns plans with dues pricing
    print("\n--- TEST 1: Catalog Plans and Pricing (6.1-C18) ---")
    plans_resp = requests.get(f"{API_BASE}/v1/subscriptions/plans", headers=HEADERS)
    assert plans_resp.status_code == 200, f"Plans fetch failed: {plans_resp.text}"
    plans = plans_resp.json().get('plans', [])
    assert len(plans) >= 4, f"Expected at least 4 plans, got {len(plans)}"
    plan_15 = next((p for p in plans if p['code'] == 'PLAN_15'), None)
    assert plan_15 is not None, "PLAN_15 not found"
    assert float(plan_15['monthly_price_usd']) > 0, "Monthly price must be > 0"
    assert float(plan_15['annual_price_usd']) > 0, "Annual price must be > 0"
    print(f"[PASS] 6.1-C18: Plans endpoint live. PLAN_15 monthly={plan_15['monthly_price_usd']}, annual={plan_15['annual_price_usd']}")

    # 2. Onboard a new member with PLAN_15
    print("\n--- TEST 2: Onboard Member with Plan & Draft Schedule (6.1-C01, 6.1-C03, 6.1-C18) ---")
    uniq = uuid.uuid4().hex[:6]
    onboard_resp = requests.post(f"{API_BASE}/v1/members/onboard", headers=HEADERS, json={
        "first_name": "Julian",
        "last_name": f"Lennon_{uniq}",
        "preferred_name": "Jules",
        "email": f"julian.{uniq}@test.com",
        "phone": "713.555.0188",
        "date_of_birth": "1983-04-08",
        "drivers_license_number": f"TX-PAY-{uniq.upper()}",
        "drivers_license_state": "TX",
        "primary_location_code": "HOU",
        "plan_code": "PLAN_15",
        "planned_start_date": "2026-11-01"
    })
    assert onboard_resp.status_code == 201, f"Onboarding failed: {onboard_resp.text}"
    member = onboard_resp.json().get('member', {})
    member_id = member.get('member_id')
    assert member_id is not None
    assert member.get('status') == 'pending'
    assert member.get('member_number') is None
    print(f"[PASS] Member created: ID {member_id}, status=pending, no member_number")

    # 3. Check Payment Schedule in Draft
    print("\n--- TEST 3: Dues Doctrine (Rule 6.1-R14, 6.1-C19: 12 Equal Payments, No Proration, on the 1st) ---")
    sched_resp = requests.get(f"{API_BASE}/v1/members/{member_id}/payment-schedule", headers=HEADERS)
    assert sched_resp.status_code == 200, f"Schedule fetch failed: {sched_resp.text}"
    sched = sched_resp.json().get('payment_schedule', {})
    assert sched.get('installment_count') == 12, f"Expected 12 installments, got {sched.get('installment_count')}"
    installments = sched.get('installments', [])
    assert len(installments) == 12, f"Expected 12 installments array, got {len(installments)}"
    
    # Check Installment 1 and subsequent installments
    inst1 = installments[0]
    assert inst1['installment_number'] == 1
    assert inst1['due_date'] == "2026-11-01"
    
    for i, inst in enumerate(installments):
        assert inst['installment_number'] == i + 1
        assert float(inst['amount']) == float(sched['installment_amount'])
        # Verify day is 01
        day = inst['due_date'].split('-')[2]
        assert day == '01', f"Installment {i+1} due_date {inst['due_date']} does not fall on the 1st!"
    print(f"[PASS] 6.1-R14 & 6.1-C19: Exactly 12 equal installments of ${sched['installment_amount']}, all due on the 1st, zero proration")

    # 4. Activation without Payment Arrangement is REFUSED (6.1-R09, 6.1-C20)
    print("\n--- TEST 4: Refuse Activation Without Payment Arrangement (Rule 6.1-R09, 6.1-C20) ---")
    refuse_resp = requests.post(f"{API_BASE}/v1/members/{member_id}/activate", headers=HEADERS, json={
        "payment_arrangement_confirmed": False
    })
    assert refuse_resp.status_code == 400, f"Expected 400, got {refuse_resp.status_code}: {refuse_resp.text}"
    print(f"[PASS] 6.1-C20: Activation refused with HTTP 400 when payment_arrangement_confirmed=false")

    # 5. Set Payment Arrangement (Card / ACH / Wire)
    print("\n--- TEST 5: Record Payment Arrangement (Rule 6.1-R09) ---")
    arr_resp = requests.post(f"{API_BASE}/v1/members/{member_id}/payment-arrangement", headers=HEADERS, json={
        "payment_method_type": "Card",
        "payment_arrangement_confirmed": True,
        "billing_email": f"billing.{uniq}@test.com",
        "notes": "Amex Platinum on file via secure portal agreement"
    })
    assert arr_resp.status_code == 200, f"Payment arrangement failed: {arr_resp.text}"
    arr_data = arr_resp.json().get('payment_arrangement', {})
    assert arr_data.get('payment_arrangement_confirmed') is True
    assert arr_data.get('payment_method_type') == 'Card'
    print(f"[PASS] 6.1-R09: Payment arrangement recorded (Card, confirmed=True)")

    # 6. Activate Member (Rule 6.1-R10, 6.1-C21, 6.1-C23, 6.1-C26, 6.1-C28, 6.1-C31)
    print("\n--- TEST 6: Atomic Activation, Start Date Recomputation, Schedule Activation (6.1-C23, C28, C31) ---")
    # Activate on 2026-11-15 (Late activation relative to planned 2026-11-01)
    act_resp = requests.post(f"{API_BASE}/v1/members/{member_id}/activate", headers=HEADERS, json={
        "payment_arrangement_confirmed": True,
        "activation_date": "2026-11-15",
        "joining_bonus_points": 50
    })
    assert act_resp.status_code == 200, f"Activation failed: {act_resp.text}"
    act = act_resp.json().get('activation', {})
    assert act.get('status') == 'active'
    assert act.get('member_seq') is not None
    assert act.get('member_number') is not None
    assert act.get('member_since') == '2026-11-15'
    assert act.get('points_balance') >= 50
    print(f"[PASS] 6.1-C28: Minted seq={act.get('member_seq')}, number={act.get('member_number')}, since={act.get('member_since')}")
    print(f"[PASS] 6.1-C26: Joining bonus posted (balance={act.get('points_balance')})")

    # 7. Check Recomputed Payment Schedule after Activation (6.1-C31)
    print("\n--- TEST 7: Recomputed Schedule on Activation (6.1-C31) ---")
    active_sched_resp = requests.get(f"{API_BASE}/v1/members/{member_id}/payment-schedule", headers=HEADERS)
    active_sched = active_sched_resp.json().get('payment_schedule', {})
    assert active_sched.get('status') == 'Active'
    active_insts = active_sched.get('installments', [])
    assert len(active_insts) == 12
    # Installment 1 due at activation (2026-11-15), remaining 11 on the 1st
    assert active_insts[0]['due_date'] == '2026-11-15'
    assert active_insts[0]['status'] == 'paid'
    assert active_insts[1]['due_date'] == '2026-12-01'
    assert active_insts[1]['status'] == 'pending'
    assert active_insts[11]['due_date'] == '2027-10-01'
    print(f"[PASS] 6.1-C31: Recomputed schedule active: Month 1 at activation (2026-11-15), Months 2-12 on 1st of each succeeding month")

    print("\n" + "=" * 80)
    print("ALL GUIDE 6.1 PAYMENT ARRANGEMENT & DUES SCHEDULE TESTS PASSED!")
    print("=" * 80)

if __name__ == '__main__':
    run_tests()
