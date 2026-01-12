#!/bin/bash

set -e

REPO_DIR="/opt/acs_resources"
GIT_REPO="https://github.com/sysscrew/acs_resourses.git"
GIT_TOKEN="SECRET_TOKEN-CHANGE_PLEASE"
GIT_USER="ACS Updater"
GIT_EMAIL="updater@example.com"

download_file() {
    local url="$1"
    local output="$2"
    echo "Downloading $url ..."
    if ! curl -s -f -L "$url" -o "$output"; then
        echo "Error downloading $url" >&2
        exit 1
    fi
}

check_commands() {
    for cmd in curl dig sort uniq git; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: $cmd is required but not installed." >&2
            exit 1
        fi
    done
}

setup_repository() {
    if [ ! -d "$REPO_DIR/.git" ]; then
        echo "Cloning repository..."
        REPO_URL="https://${GIT_TOKEN}@github.com/sysscrew/acs_resourses.git"
        git clone "$REPO_URL" "$REPO_DIR"
    fi
    
    cd "$REPO_DIR"
    
    git config user.name "$GIT_USER"
    git config user.email "$GIT_EMAIL"
    
    git pull origin main
}

commit_and_push() {
    cd "$REPO_DIR"
    
    if git diff --quiet && git diff --staged --quiet; then
        echo "No changes to commit"
        return 0
    fi
    
    echo "Committing changes..."
    git add .
    git commit -m "Update lists: $(date '+%Y-%m-%d %H:%M:%S')"
    
    echo "Pushing to repository..."
    if git push origin main; then
        echo "Changes pushed successfully"
    else
        echo "Failed to push changes" >&2
        exit 1
    fi
}

check_commands

setup_repository

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

echo "Processing domain lists..."
download_file "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/refs/heads/main/domains_all.lst" "$temp_dir/domains1.tmp"
download_file "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/refs/heads/main/community.lst" "$temp_dir/domains2.tmp"
cat "$temp_dir/domains1.tmp" "$temp_dir/domains2.tmp" | sort -u > "$temp_dir/domains_merged.tmp"

cp "$temp_dir/domains_merged.tmp" "$REPO_DIR/domains.lst"

echo "Processing IP lists..."
download_file "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/refs/heads/main/ipsum.lst" "$temp_dir/ips1.tmp"
download_file "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/refs/heads/main/community_ips.lst" "$temp_dir/ips2.tmp"
cat "$temp_dir/ips1.tmp" "$temp_dir/ips2.tmp" | sort -u > "$temp_dir/ips_merged.tmp"

cp "$temp_dir/ips_merged.tmp" "$REPO_DIR/ipsum.lst"

if [[ -f "$REPO_DIR/exclude.lst" ]]; then
    echo "Excluding domains from exclude.lst..."
    grep_pattern_file="$temp_dir/exclude_pattern.tmp"
    sed 's/\./\\./g' "$REPO_DIR/exclude.lst" | sed 's/^/^/' | sed 's/$/$/' > "$grep_pattern_file"
    
    if [[ -s "$grep_pattern_file" ]]; then
        grep -v -f "$grep_pattern_file" "$REPO_DIR/domains.lst" > "$temp_dir/domains_filtered.tmp"
        mv "$temp_dir/domains_filtered.tmp" "$REPO_DIR/domains.lst"
    fi
fi

if [[ -f "$REPO_DIR/exclude.lst" ]]; then
    echo "Resolving domains from exclude.lst..."
    
    resolved_ips="$temp_dir/resolved_ips.tmp"
    
    while IFS= read -r domain || [[ -n "$domain" ]]; do
        domain=$(echo "$domain" | xargs)
        if [[ -n "$domain" ]]; then
            echo "Resolving $domain..."
            dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' >> "$resolved_ips" || true
        fi
    done < "$REPO_DIR/exclude.lst"
    
    if [[ -f "$resolved_ips" ]]; then
        sort -u "$resolved_ips" > "$temp_dir/unique_ips.tmp"
        
        if [[ -f "$REPO_DIR/ip.lst" ]]; then
            cat "$REPO_DIR/ip.lst" "$temp_dir/unique_ips.tmp" | sort -u > "$temp_dir/combined_ips.tmp"
        else
            cp "$temp_dir/unique_ips.tmp" "$temp_dir/combined_ips.tmp"
        fi
        
        cp "$temp_dir/combined_ips.tmp" "$REPO_DIR/ip.lst"
    fi
fi

if [[ -f "$REPO_DIR/ip.lst" ]] && [[ -s "$REPO_DIR/ip.lst" ]]; then
    echo "Excluding IPs from ip.lst..."
    
    ip_pattern_file="$temp_dir/ip_pattern.tmp"
    sed 's/\./\\./g' "$REPO_DIR/ip.lst" | sed 's/^/^/' | sed 's/$/$/' > "$ip_pattern_file"
    
    if [[ -s "$ip_pattern_file" ]]; then
        grep -v -f "$ip_pattern_file" "$REPO_DIR/ipsum.lst" > "$temp_dir/ips_filtered.tmp"
        mv "$temp_dir/ips_filtered.tmp" "$REPO_DIR/ipsum.lst"
    fi
fi

commit_and_push

echo "Done!"
