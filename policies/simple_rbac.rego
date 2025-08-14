package rbac

# Simple Role-Based Access Control Policy
# Determines if a user can perform an action on a resource based on their role

default allow = false

# Allow if user has admin role
allow if {
    input.user.role == "admin"
}

# Allow read access for users with viewer role
allow if {
    input.user.role == "viewer"
    input.action == "read"
}

# Allow read/write access for users with editor role
allow if {
    input.user.role == "editor"
    input.action == "read"
}

allow if {
    input.user.role == "editor"
    input.action == "write"
}

# Allow users to read/write their own resources
allow if {
    input.user.id == input.resource.owner
    input.action == "read"
}

allow if {
    input.user.id == input.resource.owner
    input.action == "write"
}