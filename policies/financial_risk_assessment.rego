package finance.risk

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# Simplified Complex Financial Risk Assessment Policy
# Still extremely complex but with correct Rego syntax

default approve_loan = false
default risk_score = 0

# Main loan approval decision
approve_loan if {
    calculated_risk_score <= risk_tolerance
    credit_score_acceptable
    debt_to_income_acceptable
    employment_verified
    anti_money_laundering_clear
    not high_risk_jurisdiction
    collateral_sufficient
}

# Complex risk score calculation
calculated_risk_score := score if {
    base_score := base_risk_calculation
    credit_adjustment := credit_score_adjustment
    employment_adjustment := employment_stability_adjustment
    market_adjustment := market_conditions_adjustment
    
    score := base_score + credit_adjustment + employment_adjustment + market_adjustment
}

# Base risk calculation
base_risk_calculation := score if {
    applicant := input.loan_application.applicant
    dscr_impact := debt_service_coverage_impact(applicant.monthly_income, applicant.total_monthly_debt)
    ltv_impact := loan_to_value_impact(input.loan_application.amount, input.loan_application.collateral_value)
    volatility_impact := asset_volatility_impact(input.loan_application.collateral_type)
    payment_impact := payment_history_impact(applicant.payment_history)
    
    score := (dscr_impact * 0.3) + (ltv_impact * 0.25) + (volatility_impact * 0.2) + (payment_impact * 0.25)
}

# Debt service coverage ratio calculation
debt_service_coverage_impact(monthly_income, total_debt) := 100 if {
    monthly_income > 0
    total_debt > 0
    dscr := monthly_income / total_debt
    dscr < 1.0
}

debt_service_coverage_impact(monthly_income, total_debt) := 75 if {
    monthly_income > 0
    total_debt > 0
    dscr := monthly_income / total_debt
    dscr >= 1.0
    dscr < 1.25
}

debt_service_coverage_impact(monthly_income, total_debt) := 50 if {
    monthly_income > 0
    total_debt > 0
    dscr := monthly_income / total_debt
    dscr >= 1.25
    dscr < 1.5
}

debt_service_coverage_impact(monthly_income, total_debt) := 25 if {
    monthly_income > 0
    total_debt > 0
    dscr := monthly_income / total_debt
    dscr >= 1.5
    dscr < 2.0
}

debt_service_coverage_impact(monthly_income, total_debt) := 10 if {
    monthly_income > 0
    total_debt > 0
    dscr := monthly_income / total_debt
    dscr >= 2.0
}

# Loan-to-value ratio impact
loan_to_value_impact(loan_amount, collateral_value) := 80 if {
    collateral_value > 0
    ltv := (loan_amount / collateral_value) * 100
    ltv > 90
}

loan_to_value_impact(loan_amount, collateral_value) := 60 if {
    collateral_value > 0
    ltv := (loan_amount / collateral_value) * 100
    ltv > 80
    ltv <= 90
}

loan_to_value_impact(loan_amount, collateral_value) := 40 if {
    collateral_value > 0
    ltv := (loan_amount / collateral_value) * 100
    ltv > 70
    ltv <= 80
}

loan_to_value_impact(loan_amount, collateral_value) := 20 if {
    collateral_value > 0
    ltv := (loan_amount / collateral_value) * 100
    ltv > 60
    ltv <= 70
}

loan_to_value_impact(loan_amount, collateral_value) := 10 if {
    collateral_value > 0
    ltv := (loan_amount / collateral_value) * 100
    ltv <= 60
}

# Asset volatility impact
asset_volatility_impact(collateral_type) := volatility_scores[collateral_type] if {
    volatility_scores[collateral_type]
}

asset_volatility_impact(collateral_type) := 50 if {
    not volatility_scores[collateral_type]
}

volatility_scores := {
    "residential_property": 15,
    "commercial_property": 25,
    "stocks": 60,
    "bonds": 20,
    "commodities": 70,
    "cryptocurrency": 90,
    "art_collectibles": 80,
    "vehicles": 45
}

# Payment history analysis
payment_history_impact(payment_history) := 80 if {
    count(payment_history) > 0
    severe_delinquencies := count([p | p := payment_history[_]; p.days_late > 90])
    severe_rate := severe_delinquencies / count(payment_history)
    severe_rate > 0.1
}

payment_history_impact(payment_history) := 60 if {
    count(payment_history) > 0
    late_payments := count([p | p := payment_history[_]; p.days_late > 0])
    late_payment_rate := late_payments / count(payment_history)
    severe_delinquencies := count([p | p := payment_history[_]; p.days_late > 90])
    severe_rate := severe_delinquencies / count(payment_history)
    severe_rate <= 0.1
    late_payment_rate > 0.3
}

payment_history_impact(payment_history) := 20 if {
    count(payment_history) > 0
    late_payments := count([p | p := payment_history[_]; p.days_late > 0])
    late_payment_rate := late_payments / count(payment_history)
    severe_delinquencies := count([p | p := payment_history[_]; p.days_late > 90])
    severe_rate := severe_delinquencies / count(payment_history)
    severe_rate <= 0.1
    late_payment_rate > 0.1
    late_payment_rate <= 0.3
}

payment_history_impact(payment_history) := 5 if {
    count(payment_history) > 0
    late_payments := count([p | p := payment_history[_]; p.days_late > 0])
    late_payment_rate := late_payments / count(payment_history)
    severe_delinquencies := count([p | p := payment_history[_]; p.days_late > 90])
    severe_rate := severe_delinquencies / count(payment_history)
    severe_rate <= 0.1
    late_payment_rate <= 0.1
}

payment_history_impact(payment_history) := 0 if {
    count(payment_history) == 0
}

# Credit score adjustment
credit_score_adjustment := -20 if {
    scores := input.loan_application.applicant.credit_scores
    weighted_score := (scores.experian * 0.4) + (scores.equifax * 0.35) + (scores.transunion * 0.25)
    weighted_score >= 800
}

credit_score_adjustment := -10 if {
    scores := input.loan_application.applicant.credit_scores
    weighted_score := (scores.experian * 0.4) + (scores.equifax * 0.35) + (scores.transunion * 0.25)
    weighted_score >= 750
    weighted_score < 800
}

credit_score_adjustment := 0 if {
    scores := input.loan_application.applicant.credit_scores
    weighted_score := (scores.experian * 0.4) + (scores.equifax * 0.35) + (scores.transunion * 0.25)
    weighted_score >= 700
    weighted_score < 750
}

credit_score_adjustment := 15 if {
    scores := input.loan_application.applicant.credit_scores
    weighted_score := (scores.experian * 0.4) + (scores.equifax * 0.35) + (scores.transunion * 0.25)
    weighted_score >= 650
    weighted_score < 700
}

credit_score_adjustment := 30 if {
    scores := input.loan_application.applicant.credit_scores
    weighted_score := (scores.experian * 0.4) + (scores.equifax * 0.35) + (scores.transunion * 0.25)
    weighted_score >= 600
    weighted_score < 650
}

credit_score_adjustment := 50 if {
    scores := input.loan_application.applicant.credit_scores
    weighted_score := (scores.experian * 0.4) + (scores.equifax * 0.35) + (scores.transunion * 0.25)
    weighted_score < 600
}

# Employment stability adjustment
employment_stability_adjustment := adjustment if {
    employment := input.loan_application.applicant.employment
    industry_risk := industry_risk_factors[employment.industry]
    tenure_months := employment.tenure_months
    
    tenure_score := employment_tenure_score(tenure_months)
    title_stability := job_title_stability_score(employment.title)
    
    adjustment := (industry_risk + tenure_score + title_stability) / 3
}

employment_tenure_score(tenure_months) := -10 if {
    tenure_months >= 60  # 5 years
}

employment_tenure_score(tenure_months) := -5 if {
    tenure_months >= 24  # 2 years
    tenure_months < 60
}

employment_tenure_score(tenure_months) := 0 if {
    tenure_months >= 12  # 1 year
    tenure_months < 24
}

employment_tenure_score(tenure_months) := 20 if {
    tenure_months < 12
}

# Industry risk factors
industry_risk_factors := {
    "technology": -5,
    "healthcare": -10,
    "government": -15,
    "education": -8,
    "finance": -5,
    "manufacturing": 5,
    "retail": 10,
    "hospitality": 15,
    "oil_gas": 20,
    "construction": 12,
    "transportation": 8
}

# Job title stability scoring
job_title_stability_score(title) := -10 if {
    stable_titles := {"engineer", "manager", "director", "analyst", "consultant", "teacher", "nurse", "doctor"}
    title_lower := lower(title)
    some stable_title in stable_titles
    contains(title_lower, stable_title)
}

job_title_stability_score(title) := 15 if {
    volatile_titles := {"sales", "commission", "freelance", "contractor", "seasonal"}
    title_lower := lower(title)
    some volatile_title in volatile_titles
    contains(title_lower, volatile_title)
}

job_title_stability_score(title) := 0 if {
    stable_titles := {"engineer", "manager", "director", "analyst", "consultant", "teacher", "nurse", "doctor"}
    volatile_titles := {"sales", "commission", "freelance", "contractor", "seasonal"}
    title_lower := lower(title)
    
    not any_stable_match(title_lower, stable_titles)
    not any_volatile_match(title_lower, volatile_titles)
}

any_stable_match(title_lower, stable_titles) if {
    some stable_title in stable_titles
    contains(title_lower, stable_title)
}

any_volatile_match(title_lower, volatile_titles) if {
    some volatile_title in volatile_titles
    contains(title_lower, volatile_title)
}

# Market conditions adjustment
market_conditions_adjustment := adjustment if {
    economic_data := data.economic_indicators
    rate_impact := interest_rate_impact(economic_data.federal_funds_rate)
    unemployment_impact := unemployment_rate_impact(economic_data.unemployment_rate)
    gdp_impact := gdp_growth_impact(economic_data.gdp_growth_rate)
    volatility_impact := market_volatility_impact(economic_data.market_volatility_index)
    
    adjustment := (rate_impact + unemployment_impact + gdp_impact + volatility_impact) / 4
}

# Interest rate impact
interest_rate_impact(current_rate) := 0 if current_rate < 3
interest_rate_impact(current_rate) := 5 if {
    current_rate >= 3
    current_rate < 5
}
interest_rate_impact(current_rate) := 10 if {
    current_rate >= 5
    current_rate < 7
}
interest_rate_impact(current_rate) := 20 if current_rate >= 7

# Unemployment rate impact
unemployment_rate_impact(unemployment_rate) := 0 if unemployment_rate < 4
unemployment_rate_impact(unemployment_rate) := 5 if {
    unemployment_rate >= 4
    unemployment_rate < 6
}
unemployment_rate_impact(unemployment_rate) := 10 if {
    unemployment_rate >= 6
    unemployment_rate < 8
}
unemployment_rate_impact(unemployment_rate) := 20 if unemployment_rate >= 8

# GDP growth impact
gdp_growth_impact(gdp_growth) := -10 if gdp_growth > 3
gdp_growth_impact(gdp_growth) := -5 if {
    gdp_growth > 2
    gdp_growth <= 3
}
gdp_growth_impact(gdp_growth) := 0 if {
    gdp_growth > 0
    gdp_growth <= 2
}
gdp_growth_impact(gdp_growth) := 10 if {
    gdp_growth > -2
    gdp_growth <= 0
}
gdp_growth_impact(gdp_growth) := 20 if gdp_growth <= -2

# Market volatility impact
market_volatility_impact(vix) := 0 if vix < 15
market_volatility_impact(vix) := 5 if {
    vix >= 15
    vix < 25
}
market_volatility_impact(vix) := 10 if {
    vix >= 25
    vix < 35
}
market_volatility_impact(vix) := 20 if vix >= 35

# Validation rules
credit_score_acceptable if {
    min_score := risk_based_min_credit_score
    scores := input.loan_application.applicant.credit_scores
    weighted_score := (scores.experian * 0.4) + (scores.equifax * 0.35) + (scores.transunion * 0.25)
    weighted_score >= min_score
}

risk_based_min_credit_score := 750 if {
    input.loan_application.amount > 1000000
}

risk_based_min_credit_score := 700 if {
    input.loan_application.amount > 500000
    input.loan_application.amount <= 1000000
}

risk_based_min_credit_score := 650 if {
    input.loan_application.amount > 100000
    input.loan_application.amount <= 500000
}

risk_based_min_credit_score := 600 if {
    input.loan_application.amount <= 100000
}

debt_to_income_acceptable if {
    applicant := input.loan_application.applicant
    dti := (applicant.total_monthly_debt + input.loan_application.monthly_payment) / applicant.monthly_income
    dti <= 0.43
}

employment_verified if {
    employment := input.loan_application.applicant.employment
    employment.verified == true
    employment.tenure_months >= 12
    employment.income_verified == true
}

anti_money_laundering_clear if {
    applicant := input.loan_application.applicant
    not applicant.id in data.sanctions_lists.ofac
    not applicant.id in data.sanctions_lists.eu
    not applicant.id in data.sanctions_lists.un
    not applicant.id in data.pep_lists.high_risk
    not applicant.id in data.adverse_media.financial_crimes
}

high_risk_jurisdiction if {
    applicant := input.loan_application.applicant
    applicant.country in data.high_risk_countries
}

collateral_sufficient if {
    loan_amount := input.loan_application.amount
    collateral_value := input.loan_application.collateral_value
    required_ltv := required_loan_to_value_ratio
    (loan_amount / collateral_value) <= required_ltv
}

required_loan_to_value_ratio := 0.8 if {
    input.loan_application.collateral_type == "residential_property"
}

required_loan_to_value_ratio := 0.7 if {
    input.loan_application.collateral_type == "commercial_property"
}

required_loan_to_value_ratio := 0.6 if {
    input.loan_application.collateral_type == "vehicles"
}

required_loan_to_value_ratio := 0.5 if {
    input.loan_application.collateral_type != "residential_property"
    input.loan_application.collateral_type != "commercial_property" 
    input.loan_application.collateral_type != "vehicles"
}

risk_tolerance := 30 if {
    input.loan_application.amount < 100000
}

risk_tolerance := 25 if {
    input.loan_application.amount >= 100000
    input.loan_application.amount < 500000
}

risk_tolerance := 20 if {
    input.loan_application.amount >= 500000
    input.loan_application.amount < 1000000
}

risk_tolerance := 15 if {
    input.loan_application.amount >= 1000000
}