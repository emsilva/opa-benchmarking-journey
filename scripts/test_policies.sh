#!/bin/bash

echo "=== OPA Benchmarking Journey - Policy Testing ==="
echo ""

# Simple RBAC Test
echo "1. Simple RBAC Policy (Admin Access)"
echo '{"user": {"id": "user_001", "role": "admin"}, "action": "delete", "resource": {"owner": "user_002"}}' | \
./opa eval -d policies/simple_rbac.rego "data.rbac.allow" --format pretty
echo ""

echo "2. Simple RBAC Policy (Editor Read Access)"
echo '{"user": {"id": "user_002", "role": "editor"}, "action": "read", "resource": {"owner": "user_003"}}' | \
./opa eval -d policies/simple_rbac.rego "data.rbac.allow" --format pretty
echo ""

# API Authorization Test  
echo "3. API Authorization Policy (Premium User)"
echo '{"user": {"id": "user_001", "token": "valid_jwt_token", "permissions": ["users:read"], "tier": "premium", "department": "engineering"}, "method": "GET", "path": "/api/users", "client_ip": "192.168.1.1"}' | \
./opa eval -d policies/api_authorization.rego -d data/benchmark_data.json "data.api.authz.allow" --format pretty
echo ""

# Financial Risk Assessment Test
echo "4. Financial Risk Assessment (High-Quality Applicant)"
echo '{"loan_application": {"amount": 500000, "monthly_payment": 3200, "collateral_value": 750000, "collateral_type": "residential_property", "applicant": {"id": "applicant_001", "country": "US", "monthly_income": 12000, "total_monthly_debt": 4500, "credit_scores": {"experian": 780, "equifax": 775, "transunion": 785}, "employment": {"industry": "technology", "title": "Senior Engineer", "tenure_months": 48, "verified": true, "income_verified": true}, "payment_history": [{"days_late": 0}, {"days_late": 0}, {"days_late": 0}]}}}' | \
./opa eval -d policies/financial_risk_assessment.rego -d data/benchmark_data.json "data.finance.risk.calculated_risk_score" --format pretty
echo ""

echo "5. Financial Risk Assessment (Loan Approval)"
echo '{"loan_application": {"amount": 500000, "monthly_payment": 3200, "collateral_value": 750000, "collateral_type": "residential_property", "applicant": {"id": "applicant_001", "country": "US", "monthly_income": 12000, "total_monthly_debt": 4500, "credit_scores": {"experian": 780, "equifax": 775, "transunion": 785}, "employment": {"industry": "technology", "title": "Senior Engineer", "tenure_months": 48, "verified": true, "income_verified": true}, "payment_history": [{"days_late": 0}, {"days_late": 0}, {"days_late": 0}]}}}' | \
./opa eval -d policies/financial_risk_assessment.rego -d data/benchmark_data.json "data.finance.risk.approve_loan" --format pretty
echo ""

echo "=== Policy Lines of Code Comparison ==="
echo "Simple RBAC:             $(wc -l < policies/simple_rbac.rego) lines"
echo "API Authorization:       $(wc -l < policies/api_authorization.rego) lines" 
echo "Financial Risk:          $(wc -l < policies/financial_risk_assessment.rego) lines"
echo ""

echo "=== Test complete! ==="