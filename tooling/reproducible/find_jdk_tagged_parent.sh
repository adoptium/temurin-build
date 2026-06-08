#!/bin/bash

# Function to find the parent OpenJDK commit tagged with "jdk-*"
# Usage: find_jdk_tagged_parent <commit_sha>
#
# This function traverses the commit tree from the given commit backwards
# through all parent paths until it finds a commit tagged with "jdk-*"

find_jdk_tagged_parent() {
    local start_commit="$1"
    
    if [ -z "$start_commit" ]; then
        echo "Error: No commit SHA provided" >&2
        return 1
    fi
    
    # Verify the commit exists
    if ! git rev-parse --verify "$start_commit^{commit}" >/dev/null 2>&1; then
        echo "Error: Invalid commit SHA: $start_commit" >&2
        return 1
    fi
    
    # Use git rev-list to traverse all reachable commits from the starting point
    # Skip the starting commit itself (use ^) and check parents for jdk-* tag
    local first_commit=true
    while IFS= read -r commit; do
        # Skip the first commit (the starting commit itself)
        if [ "$first_commit" = true ]; then
            first_commit=false
            continue
        fi
        
        # Get all tags pointing to this commit
        local tags=$(git tag --points-at "$commit" 2>/dev/null)
        
        # Check if any tag starts with "jdk-"
        if echo "$tags" | grep -q "^jdk-"; then
            echo "$commit"
            return 0
        fi
    done < <(git rev-list "$start_commit")
    
    # No jdk-* tagged commit found
    echo "Error: No commit tagged with 'jdk-*' found in ancestry of $start_commit" >&2
    return 1
}

# If script is executed directly (not sourced), run the function
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    find_jdk_tagged_parent "$@"
fi

# Made with Bob
