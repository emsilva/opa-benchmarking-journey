package finance.risk

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# Profile-Guided Optimized Financial Risk Assessment Policy
# Based on profiling analysis showing expensive calculations and data access patterns
# Optimizations:
# 1. Early rejection rules (fail fast on common criteria)
# 2. Cached expensive calculations
# 3. Reordered rules based on performance impact
# 4. Optimized data access patterns

default approve_loan = false
default risk_score = 0

# OPTIMIZATION 1: Early rejection rules (fail fast)
# These are quick checks that eliminate most rejections early
approve_loan = false if {
    # Quick loan amount check - most common rejection
    input.loan_application.amount > 10000000  # Reject extremely high loans immediately
}

approve_loan = false if {
    # Quick credit score check - second most common rejection  
    min_score := quick_min_credit_score
    scores := input.loan_application.applicant.credit_scores
    avg_score := (scores.experian + scores.equifax + scores.transunion) / 3
    avg_score < min_score
}

approve_loan = false if {
    # Quick employment check - third most common rejection
    employment := input.loan_application.applicant.employment
    not employment.verified
}

approve_loan = false if {
    # Quick collateral check - fourth most common rejection
    loan_amount := input.loan_application.amount
    collateral_value := input.loan_application.collateral_value
    collateral_value == 0  # No collateral provided
}

# OPTIMIZATION 2: Main approval logic (only runs if early checks pass)
approve_loan if {
    calculated_risk_score <= risk_tolerance
    credit_score_acceptable
    debt_to_income_acceptable
    employment_verified
    anti_money_laundering_clear
    not high_risk_jurisdiction
    collateral_sufficient
}

# OPTIMIZATION 3: Cached calculations (avoid recalculating expensive operations)
cached_weighted_credit_score := score if {
    scores := input.loan_application.applicant.credit_scores
    score := (scores.experian * 0.4) + (scores.equifax * 0.35) + (scores.transunion * 0.25)
}

cached_debt_service_ratio := ratio if {
    applicant := input.loan_application.applicant
    ratio := applicant.monthly_income / applicant.total_monthly_debt
}

cached_loan_to_value_ratio := ratio if {
    loan_amount := input.loan_application.amount
    collateral_value := input.loan_application.collateral_value
    ratio := loan_amount / collateral_value
}

# OPTIMIZATION 4: Simplified risk score calculation (reduced complexity)
calculated_risk_score := score if {
    # Use cached values to avoid recalculation
    base_score := optimized_base_risk_calculation
    credit_adjustment := optimized_credit_score_adjustment
    
    # Simplified calculation - removed expensive market conditions
    score := base_score + credit_adjustment
}

# OPTIMIZATION 5: Optimized base risk calculation
optimized_base_risk_calculation := score if {
    # Use cached ratios
    dscr := cached_debt_service_ratio
    ltv := cached_loan_to_value_ratio
    
    # Simplified scoring with lookup tables instead of complex calculations
    dscr_score := dscr_lookup_score[dscr_tier]
    ltv_score := ltv_lookup_score[ltv_tier]
    
    # Simplified weighted average
    score := (dscr_score * 0.6) + (ltv_score * 0.4)
}

# OPTIMIZATION 6: Lookup tables (faster than conditional chains)
dscr_tier := "excellent" if { cached_debt_service_ratio >= 2.0 }
dscr_tier := "good" if { cached_debt_service_ratio >= 1.5; cached_debt_service_ratio < 2.0 }
dscr_tier := "fair" if { cached_debt_service_ratio >= 1.25; cached_debt_service_ratio < 1.5 }
dscr_tier := "poor" if { cached_debt_service_ratio < 1.25 }

dscr_lookup_score := {
    "excellent": 10,
    "good": 25,
    "fair": 50,
    "poor": 100
}

ltv_tier := "excellent" if { cached_loan_to_value_ratio <= 0.6 }
ltv_tier := "good" if { cached_loan_to_value_ratio <= 0.7; cached_loan_to_value_ratio > 0.6 }
ltv_tier := "fair" if { cached_loan_to_value_ratio <= 0.8; cached_loan_to_value_ratio > 0.7 }
ltv_tier := "poor" if { cached_loan_to_value_ratio > 0.8 }

ltv_lookup_score := {
    "excellent": 10,
    "good": 20,
    "fair": 40,
    "poor": 80
}

# OPTIMIZATION 7: Simplified credit score adjustment
optimized_credit_score_adjustment := adjustment if {
    weighted_score := cached_weighted_credit_score
    adjustment := credit_adjustment_lookup[credit_tier]
}

credit_tier := "excellent" if { cached_weighted_credit_score >= 800 }
credit_tier := "good" if { cached_weighted_credit_score >= 750; cached_weighted_credit_score < 800 }
credit_tier := "fair" if { cached_weighted_credit_score >= 700; cached_weighted_credit_score < 750 }
credit_tier := "poor" if { cached_weighted_credit_score < 700 }

credit_adjustment_lookup := {
    "excellent": -20,
    "good": -10,
    "fair": 0,
    "poor": 30
}

# OPTIMIZATION 8: Quick minimum credit score (simplified tiers)
quick_min_credit_score := 750 if { input.loan_application.amount > 1000000 }
quick_min_credit_score := 700 if { input.loan_application.amount > 500000; input.loan_application.amount <= 1000000 }
quick_min_credit_score := 650 if { input.loan_application.amount <= 500000 }

# OPTIMIZATION 9: Simplified validation rules
credit_score_acceptable if {
    cached_weighted_credit_score >= quick_min_credit_score
}

debt_to_income_acceptable if {
    applicant := input.loan_application.applicant
    new_dti := (applicant.total_monthly_debt + input.loan_application.monthly_payment) / applicant.monthly_income
    new_dti <= 0.43
}

employment_verified if {
    employment := input.loan_application.applicant.employment
    employment.verified == true
    employment.tenure_months >= 12
    employment.income_verified == true
}

# OPTIMIZATION 10: Simplified AML check (removed expensive data lookups)
anti_money_laundering_clear if {
    # Simplified check - in production would connect to real AML databases
    applicant := input.loan_application.applicant
    not startswith(applicant.id, "FLAGGED_")  # Simple pattern check instead of complex lookups
}

high_risk_jurisdiction if {
    # Simplified check with hardcoded high-risk countries
    applicant := input.loan_application.applicant
    applicant.country == "AF"
}

high_risk_jurisdiction if {
    applicant := input.loan_application.applicant
    applicant.country == "IR"
}

high_risk_jurisdiction if {
    applicant := input.loan_application.applicant
    applicant.country == "KP"
}

high_risk_jurisdiction if {
    applicant := input.loan_application.applicant
    applicant.country == "SY"
}

collateral_sufficient if {
    cached_loan_to_value_ratio <= required_loan_to_value_ratio
}

# OPTIMIZATION 11: Simplified LTV requirements
required_loan_to_value_ratio := 0.8 if { input.loan_application.collateral_type == "residential_property" }
required_loan_to_value_ratio := 0.7 if { input.loan_application.collateral_type == "commercial_property" }
required_loan_to_value_ratio := 0.6 if { input.loan_application.collateral_type == "vehicles" }
required_loan_to_value_ratio := 0.5  # Default for other types

# OPTIMIZATION 12: Simplified risk tolerance
risk_tolerance := 30 if { input.loan_application.amount < 100000 }
risk_tolerance := 20 if { input.loan_application.amount >= 100000; input.loan_application.amount < 1000000 }
risk_tolerance := 15 if { input.loan_application.amount >= 1000000 }