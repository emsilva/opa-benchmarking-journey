package api.authz

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# API Authorization Policy with rate limiting, time-based access, and resource scoping
# Moderate complexity with multiple conditions and helper functions

default allow = false

# Main authorization decision
allow if {
    is_authenticated
    has_required_permissions
    not is_rate_limited
    is_within_time_window
    not is_resource_restricted
}

# Check if user is properly authenticated
is_authenticated if {
    input.user.id
    input.user.token
    valid_token
}

# Validate JWT token format and expiration
valid_token if {
    token := input.user.token
    parts := split(token, ".")
    count(parts) == 3
    payload := json.unmarshal(base64url.decode(parts[1]))
    payload.exp > time.now_ns() / 1000000000
}

# Check if user has required permissions for the requested action
has_required_permissions if {
    required_permission := permission_mapping[input.method][input.path]
    required_permission in input.user.permissions
}

# Permission mapping based on HTTP method and path patterns
permission_mapping := {
    "GET": {
        "/api/users": "users:read",
        "/api/orders": "orders:read",
        "/api/products": "products:read",
        "/api/analytics": "analytics:read"
    },
    "POST": {
        "/api/users": "users:create",
        "/api/orders": "orders:create",
        "/api/products": "products:create"
    },
    "PUT": {
        "/api/users": "users:update",
        "/api/orders": "orders:update",
        "/api/products": "products:update"
    },
    "DELETE": {
        "/api/users": "users:delete",
        "/api/orders": "orders:delete",
        "/api/products": "products:delete"
    }
}

# Rate limiting check
is_rate_limited if {
    user_requests := [req | req := data.request_log[_]; req.user_id == input.user.id]
    recent_requests := [req | req := user_requests[_]; req.timestamp > (time.now_ns() - 60000000000)]
    count(recent_requests) >= rate_limit_for_user
}

# Dynamic rate limit based on user tier
rate_limit_for_user := limit if {
    input.user.tier == "premium"
    limit := 1000
} else := limit if {
    input.user.tier == "standard"
    limit := 100
} else := 50

# Time-based access control (simplified for server compatibility)
is_within_time_window if {
    # For benchmark purposes, assume engineering has 24/7 access
    input.user.department == "engineering"
}

is_within_time_window if {
    # For other departments, assume business hours (simplified)
    input.user.department == "sales"
    # In real implementation, would check current time
    true  # Simplified for benchmarking
}

is_within_time_window if {
    input.user.department == "support"
    true
}

is_within_time_window if {
    input.user.department == "finance"
    true
}

# Department-based time windows
time_windows := {
    "engineering": {"start": 0, "end": 23},
    "sales": {"start": 8, "end": 18},
    "support": {"start": 6, "end": 22},
    "finance": {"start": 9, "end": 17}
}

# Resource restriction based on data classification
is_resource_restricted if {
    resource_classification := classify_resource(input.path)
    resource_classification == "confidential"
    not "data:confidential" in input.user.permissions
}

# Classify resource based on path patterns
classify_resource(path) := "confidential" if {
    confidential_patterns := ["/api/financials", "/api/payroll", "/api/contracts"]
    some pattern in confidential_patterns
    contains(path, pattern)
} else := "internal" if {
    internal_patterns := ["/api/employees", "/api/departments"]
    some pattern in internal_patterns
    contains(path, pattern)
} else := "public"

# Audit logging helper
audit_log := {
    "user_id": input.user.id,
    "action": input.method,
    "resource": input.path,
    "timestamp": time.now_ns(),
    "decision": allow,
    "ip_address": input.client_ip
}