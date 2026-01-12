#!/bin/bash

set -e

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
    for cmd in curl dig sort uniq; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: $cmd is required but not installed." >&2
            exit 1
        fi
    done
}

check_commands

temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT

echo "Processing domain lists..."
download_file "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/refs/heads/main/domains_all.lst" "$temp_dir/domains1.tmp"
download_file "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/refs/heads/main/community.lst" "$temp_dir/domains2.tmp"
cat "$temp_dir/domains1.tmp" "$temp_dir/domains2.tmp" | sort -u > "$temp_dir/domains_merged.tmp"

cp "$temp_dir/domains_merged.tmp" /etc/domains.lst
chmod 644 /etc/domains.lst

echo "Processing IP lists..."
download_file "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/refs/heads/main/ipsum.lst" "$temp_dir/ips1.tmp"
download_file "https://raw.githubusercontent.com/1andrevich/Re-filter-lists/refs/heads/main/community_ips.lst" "$temp_dir/ips2.tmp"
cat "$temp_dir/ips1.tmp" "$temp_dir/ips2.tmp" | sort -u > "$temp_dir/ips_merged.tmp"

cp "$temp_dir/ips_merged.tmp" /etc/ipsum.lst
chmod 644 /etc/ipsum.lst

if [[ -f /etc/exclude.lst ]]; then
    echo "Excluding domains from /etc/exclude.lst..."
    grep_pattern_file="$temp_dir/exclude_pattern.tmp"
    sed 's/\./\\./g' /etc/exclude.lst | sed 's/^/^/' | sed 's/$/$/' > "$grep_pattern_file"
    
    if [[ -s "$grep_pattern_file" ]]; then
        grep -v -f "$grep_pattern_file" /etc/domains.lst > "$temp_dir/domains_filtered.tmp"
        mv "$temp_dir/domains_filtered.tmp" /etc/domains.lst
    fi
fi

if [[ -f /etc/exclude.lst ]]; then
    echo "Resolving domains from /etc/exclude.lst..."
    
    resolved_ips="$temp_dir/resolved_ips.tmp"
    
    while IFS= read -r domain || [[ -n "$domain" ]]; do
        domain=$(echo "$domain" | xargs)
        if [[ -n "$domain" ]]; then
            echo "Resolving $domain..."
            dig +short "$domain" A 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' >> "$resolved_ips" || true
        fi
    done < /etc/exclude.lst
    
    if [[ -f "$resolved_ips" ]]; then
        sort -u "$resolved_ips" > "$temp_dir/unique_ips.tmp"
        
        if [[ -f /etc/ip.lst ]]; then
            cat /etc/ip.lst "$temp_dir/unique_ips.tmp" | sort -u > "$temp_dir/combined_ips.tmp"
        else
            cp "$temp_dir/unique_ips.tmp" "$temp_dir/combined_ips.tmp"
        fi
        
        cp "$temp_dir/combined_ips.tmp" /etc/ip.lst
        chmod 644 /etc/ip.lst
    fi
fi

if [[ -f /etc/ip.lst ]] && [[ -s /etc/ip.lst ]]; then
    echo "Excluding IPs from /etc/ip.lst..."
    
    ip_pattern_file="$temp_dir/ip_pattern.tmp"
    sed 's/\./\\./g' /etc/ip.lst | sed 's/^/^/' | sed 's/$/$/' > "$ip_pattern_file"
    
    if [[ -s "$ip_pattern_file" ]]; then
        grep -v -f "$ip_pattern_file" /etc/ipsum.lst > "$temp_dir/ips_filtered.tmp"
        mv "$temp_dir/ips_filtered.tmp" /etc/ipsum.lst
    fi
fi

echo "Done!"