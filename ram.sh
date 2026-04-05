#!/usr/bin/env bash
# =============================================================================
# Plugin: ram
# Description: Accurate RAM usage for Apple Silicon macOS (Tahoe+) and Linux
# Type: conditional (with threshold support)
# Dependencies: vm_stat + sysctl on macOS, /proc/meminfo on Linux
# =============================================================================
#
# Why this exists:
#   The built-in memory plugin has two accuracy problems on Apple Silicon:
#   1. memory_pressure reports a coarse "free percentage" that doesn't match
#      Activity Monitor.
#   2. The vm_stat fallback only counts active + wired pages, ignoring
#      compressor-occupied pages — a large category on Apple Silicon where
#      memory compression is aggressive.
#
#   This plugin matches Activity Monitor's "Memory Used" by summing:
#     active + wired + compressor (occupied by compressor) pages
#
# CONTRACT IMPLEMENTATION:
#
# State:
#   - active: Memory metrics are available
#   - inactive: Unable to read memory metrics
#
# Health:
#   - ok: Memory usage below warning threshold
#   - warning: Memory usage above warning but below critical
#   - error: Memory usage above critical threshold
#
# Context:
#   - normal_load: Memory usage is normal
#   - high_load: Memory usage is elevated (warning level)
#   - critical_load: Memory usage is critical
#
# =============================================================================

POWERKIT_ROOT="${POWERKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
. "${POWERKIT_ROOT}/src/contract/plugin_contract.sh"

# =============================================================================
# Plugin Contract: Metadata
# =============================================================================

plugin_get_metadata() {
    metadata_set "id" "ram"
    metadata_set "name" "RAM"
    metadata_set "description" "Accurate RAM usage (Activity Monitor style on macOS)"
}

# =============================================================================
# Plugin Contract: Dependencies
# =============================================================================

plugin_check_dependencies() {
    if is_macos; then
        require_cmd "vm_stat" 1
        require_cmd "sysctl" 1
    else
        [[ -f /proc/meminfo ]] || return 1
    fi
    return 0
}

# =============================================================================
# Plugin Contract: Options
# =============================================================================

plugin_declare_options() {
    declare_option "format" "string" "percent" "Display format (percent|usage|used)"
    declare_option "icon" "icon" $'\U0000efc5' "Plugin icon"
    declare_option "warning_threshold" "number" "75" "Warning threshold percentage"
    declare_option "critical_threshold" "number" "90" "Critical threshold percentage"
    declare_option "cache_ttl" "number" "5" "Cache duration in seconds"
}

# =============================================================================
# macOS Memory Detection — Activity Monitor style
# =============================================================================

_collect_macos() {
    local page_size mem_total
    page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo 16384)
    mem_total=$(sysctl -n hw.memsize 2>/dev/null || echo 0)

    # Match Activity Monitor's "Memory Used" = App Memory + Wired + Compressed
    #   App Memory  = internal (anonymous) pages - purgeable pages
    #   Wired       = wired pages
    #   Compressed  = pages occupied by compressor
    local mem_used
    mem_used=$(vm_stat 2>/dev/null | awk -v ps="$page_size" '
        function strip(s) { gsub(/[^0-9]/, "", s); return s + 0 }
        /^Anonymous pages:/             { anon       = strip($3) }
        /^Pages purgeable:/             { purgeable  = strip($3) }
        /Pages wired down:/             { wired      = strip($4) }
        /Pages occupied by compressor:/ { compressed = strip($5) }
        END {
            app = anon - purgeable
            if (app < 0) app = 0
            used_bytes = (app + wired + compressed) * ps
            printf "%d", used_bytes
        }
    ')

    [[ -z "$mem_used" || "$mem_used" == "0" ]] && { echo "0 0 0"; return; }

    local percent
    percent=$(calc_percent "$mem_used" "$mem_total")
    (( percent > 100 )) && percent=100
    (( percent < 0 )) && percent=0

    echo "$percent $mem_used $mem_total"
}

# =============================================================================
# Linux Memory Detection
# =============================================================================

_collect_linux() {
    local mem_info mem_total mem_available mem_used percent

    mem_info=$(awk '
        /^MemTotal:/ {total=$2}
        /^MemAvailable:/ {available=$2}
        /^MemFree:/ {free=$2}
        /^Buffers:/ {buffers=$2}
        /^Cached:/ {cached=$2}
        END {
            if (available > 0) { avail = available }
            else { avail = free + buffers + cached }
            print total, avail
        }
    ' /proc/meminfo 2>/dev/null)

    [[ -z "$mem_info" ]] && { echo "0 0 0"; return; }

    read -r mem_total mem_available <<< "$mem_info"
    mem_used=$((mem_total - mem_available))

    percent=$(calc_percent "$mem_used" "$mem_total")
    (( percent > 100 )) && percent=100
    (( percent < 0 )) && percent=0

    local used_bytes=$((mem_used * 1024))
    local total_bytes=$((mem_total * 1024))

    echo "$percent $used_bytes $total_bytes"
}

# =============================================================================
# Utility Functions
# =============================================================================

_bytes_to_human() {
    local bytes="${1:-0}"
    local gb=$((bytes / 1073741824))

    if [[ $gb -gt 0 ]]; then
        awk -v b="$bytes" 'BEGIN {printf "%.1fG", b / 1073741824}'
    else
        awk -v b="$bytes" 'BEGIN {printf "%.0fM", b / 1048576}'
    fi
}

# =============================================================================
# Plugin Contract: Data Collection
# =============================================================================

plugin_collect() {
    local data

    if is_macos; then
        data=$(_collect_macos)
    elif is_linux; then
        data=$(_collect_linux)
    else
        data="0 0 0"
    fi

    local percent used total
    read -r percent used total <<< "$data"

    plugin_data_set "percent" "${percent:-0}"
    plugin_data_set "used" "${used:-0}"
    plugin_data_set "total" "${total:-0}"
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

    evaluate_threshold_health "${percent:-0}" "${warn_th:-75}" "${crit_th:-90}"
}

# =============================================================================
# Plugin Contract: Context
# =============================================================================

plugin_get_context() {
    local health
    health=$(plugin_get_health)

    case "$health" in
        error)   printf 'critical_load' ;;
        warning) printf 'high_load' ;;
        *)       printf 'normal_load' ;;
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
    local format percent used total

    format=$(get_option "format")
    percent=$(plugin_data_get "percent")
    used=$(plugin_data_get "used")
    total=$(plugin_data_get "total")

    percent="${percent:-0}"

    case "$format" in
        usage)
            printf '%s/%s' "$(_bytes_to_human "$used")" "$(_bytes_to_human "$total")"
            ;;
        used)
            printf '%s' "$(_bytes_to_human "$used")"
            ;;
        percent|*)
            printf '%3d%%' "$percent"
            ;;
    esac
}

# =============================================================================
# Initialize Plugin
# =============================================================================
