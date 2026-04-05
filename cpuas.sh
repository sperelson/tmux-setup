#!/usr/bin/env bash
# =============================================================================
# Plugin: cpuas
# Description: Accurate CPU usage for macOS (Apple Silicon) and Linux
# Type: conditional (with threshold support)
# Dependencies: iostat on macOS, /proc/stat on Linux
# =============================================================================
#
# Why this exists:
#   The built-in cpu plugin uses `top -l 1` on macOS, which returns the
#   cumulative-since-boot CPU average — not a live snapshot. This inflates
#   readings significantly (often 2x the actual load).
#
#   This plugin uses `iostat -c 2 -w 1` and takes the second sample (a true
#   1-second delta), matching Activity Monitor's readings.
#
#   On Linux it uses /proc/stat delta calculations (same as the original).
#
# =============================================================================

POWERKIT_ROOT="${POWERKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
. "${POWERKIT_ROOT}/src/contract/plugin_contract.sh"

# =============================================================================
# Plugin Contract: Metadata
# =============================================================================

plugin_get_metadata() {
    metadata_set "id" "cpuas"
    metadata_set "name" "CPU"
    metadata_set "description" "Accurate CPU usage (delta-based on macOS)"
}

# =============================================================================
# Plugin Contract: Dependencies
# =============================================================================

plugin_check_dependencies() {
    if is_macos; then
        require_cmd "iostat" 1
    else
        [[ -f /proc/stat ]] || return 1
    fi
    return 0
}

# =============================================================================
# Plugin Contract: Options
# =============================================================================

plugin_declare_options() {
    declare_option "format" "string" "percent" "Display format (percent|load)"
    declare_option "icon" "icon" $'\U000f0ee0' "Plugin icon"
    declare_option "warning_threshold" "number" "70" "Warning threshold percentage"
    declare_option "critical_threshold" "number" "90" "Critical threshold percentage"
    declare_option "cache_ttl" "number" "5" "Cache duration in seconds"
}

# =============================================================================
# macOS CPU Detection — iostat delta
# =============================================================================

_collect_macos() {
    # iostat -c 2 -w 1: first line is cumulative (discard), second is 1s delta
    local line
    line=$(iostat -c 2 -w 1 2>/dev/null | tail -1)

    [[ -z "$line" ]] && { echo "0"; return; }

    # Columns: disk... cpu(us sy id) load(1m 5m 15m)
    # Extract idle from cpu columns (4th from the end, before 3 load averages)
    local percent
    percent=$(echo "$line" | awk '{
        n = NF
        idle = $(n-3)
        used = 100 - idle
        if (used < 0) used = 0
        if (used > 100) used = 100
        printf "%d", used
    }')

    echo "${percent:-0}"
}

# =============================================================================
# Linux CPU Detection — /proc/stat delta
# =============================================================================

_collect_linux() {
    local cache_file="/tmp/powerkit-cpuas-prev"
    local cpu_line prev_line

    cpu_line=$(head -1 /proc/stat 2>/dev/null)
    [[ -z "$cpu_line" ]] && { echo "0"; return; }

    prev_line=""
    [[ -f "$cache_file" ]] && prev_line=$(cat "$cache_file" 2>/dev/null)

    # Save current for next cycle
    echo "$cpu_line" > "$cache_file" 2>/dev/null

    [[ -z "$prev_line" ]] && { echo "0"; return; }

    # Calculate delta: user+nice+system+irq+softirq+steal vs idle+iowait
    local percent
    percent=$(awk -v prev="$prev_line" -v curr="$cpu_line" 'BEGIN {
        split(prev, p)
        split(curr, c)
        # fields: cpu user nice system idle iowait irq softirq steal
        prev_idle = p[5] + p[6]
        curr_idle = c[5] + c[6]
        prev_total = 0; curr_total = 0
        for (i = 2; i <= 9; i++) { prev_total += p[i]; curr_total += c[i] }
        d_total = curr_total - prev_total
        d_idle = curr_idle - prev_idle
        if (d_total > 0) printf "%d", (d_total - d_idle) * 100 / d_total
        else printf "0"
    }')

    echo "${percent:-0}"
}

# =============================================================================
# Plugin Contract: Data Collection
# =============================================================================

plugin_collect() {
    local percent

    if is_macos; then
        percent=$(_collect_macos)
    elif is_linux; then
        percent=$(_collect_linux)
    else
        percent=0
    fi

    plugin_data_set "percent" "${percent:-0}"
    plugin_data_set "available" "1"
}

# =============================================================================
# Plugin Contract: Type and Presence
# =============================================================================

plugin_get_content_type() {
    printf 'dynamic'
}

plugin_get_presence() {
    printf 'conditional'
}

# =============================================================================
# Plugin Contract: State
# =============================================================================

plugin_get_state() {
    local available
    available=$(plugin_data_get "available")
    [[ "$available" == "1" ]] && printf 'active' || printf 'inactive'
}

# =============================================================================
# Plugin Contract: Health
# =============================================================================

plugin_get_health() {
    local percent warn_th crit_th
    percent=$(plugin_data_get "percent")
    warn_th=$(get_option "warning_threshold")
    crit_th=$(get_option "critical_threshold")

    evaluate_threshold_health "${percent:-0}" "${warn_th:-70}" "${crit_th:-90}"
}

# =============================================================================
# Plugin Contract: Context
# =============================================================================

plugin_get_context() {
    local health
    health=$(plugin_get_health)

    case "$health" in
        error)   printf 'cpu_load_critical' ;;
        warning) printf 'cpu_load_high' ;;
        *)       printf 'cpu_load_ok' ;;
    esac
}

# =============================================================================
# Plugin Contract: Icon
# =============================================================================

plugin_get_icon() { get_option "icon"; }

# =============================================================================
# Plugin Contract: Render
# =============================================================================

plugin_render() {
    local percent
    percent=$(plugin_data_get "percent")
    percent="${percent:-0}"

    printf '%3d%%' "$percent"
}

# =============================================================================
# Initialize Plugin
# =============================================================================
