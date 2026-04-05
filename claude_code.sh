#!/usr/bin/env bash
# =============================================================================
# Plugin: claude_code
# Description: Display Claude Code rate limit usage (5h window / 7d reset)
# Type: conditional (hidden when no active Claude Code session)
# Dependencies: None (reads from /tmp/claude-code-ctx written by statusline.sh)
# =============================================================================

POWERKIT_ROOT="${POWERKIT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
. "${POWERKIT_ROOT}/src/contract/plugin_contract.sh"

# =============================================================================
# Plugin Contract: Metadata
# =============================================================================

plugin_get_metadata() {
    metadata_set "id" "claude_code"
    metadata_set "name" "Claude Code"
    metadata_set "description" "Display Claude Code rate limit usage (5h / 7d)"
}

# =============================================================================
# Plugin Contract: Dependencies
# =============================================================================

plugin_check_dependencies() {
    return 0
}

# =============================================================================
# Plugin Contract: Options
# =============================================================================

plugin_declare_options() {
    declare_option "icon" "icon" "󱚣" "Plugin icon (battery level based on 5h usage)"

    declare_option "warning_threshold" "number" "40" "Warning threshold for 5h percentage"
    declare_option "critical_threshold" "number" "60" "Critical threshold for 5h percentage"

    declare_option "stale_seconds" "number" "600" "Consider data stale after this many seconds"

    declare_option "cache_ttl" "number" "5" "Cache duration in seconds"
}

# =============================================================================
# Plugin Contract: Data Collection
# =============================================================================

_read_ctx_file() {
    local ctx_file="/tmp/claude-code-ctx"

    [[ -f "$ctx_file" ]] || return 1

    # Check if the file is stale
    local stale_seconds
    stale_seconds=$(get_option "stale_seconds")
    stale_seconds="${stale_seconds:-30}"

    local file_age
    if is_macos; then
        file_age=$(( $(date +%s) - $(stat -f %m "$ctx_file" 2>/dev/null || echo 0) ))
    elif is_linux; then
        file_age=$(( $(date +%s) - $(stat -c %Y "$ctx_file" 2>/dev/null || echo 0) ))
    else
        return 1
    fi

    (( file_age > stale_seconds )) && return 1

    local five_h seven_d
    read -r five_h seven_d < "$ctx_file" 2>/dev/null

    [[ "$five_h" =~ ^[0-9]+$ ]] || return 1
    [[ "$seven_d" =~ ^[0-9]+$ ]] || return 1

    printf '%s %s' "$five_h" "$seven_d"
}

plugin_collect() {
    local data
    data=$(_read_ctx_file)

    if [[ -n "$data" ]]; then
        local five_h seven_d
        read -r five_h seven_d <<< "$data"
        plugin_data_set "five_h" "$five_h"
        plugin_data_set "seven_d" "$seven_d"
        plugin_data_set "available" "1"
    else
        plugin_data_set "five_h" "0"
        plugin_data_set "seven_d" "0"
        plugin_data_set "available" "0"
    fi
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
    local five_h warn_th crit_th
    five_h=$(plugin_data_get "five_h")
    warn_th=$(get_option "warning_threshold")
    crit_th=$(get_option "critical_threshold")

    evaluate_threshold_health "${five_h:-0}" "${warn_th:-40}" "${crit_th:-60}"
}

# =============================================================================
# Plugin Contract: Context
# =============================================================================

plugin_get_context() {
    plugin_context_from_health "$(plugin_get_health)" "claude_rate"
}

# =============================================================================
# Plugin Contract: Icon
# =============================================================================

plugin_get_icon() {
    local five_h
    five_h=$(plugin_data_get "five_h")
    five_h="${five_h:-0}"

    if (( five_h >= 95 )); then
        printf '󱚡'
    elif (( five_h >= 80 )); then
        printf '󱚟'
    elif (( five_h >= 60 )); then
        printf '󱚝'
    elif (( five_h >= 40 )); then
        printf '󰚩'
    elif (( five_h >= 5 )); then
        printf '󱜙'
    else
        printf '󱚣'
    fi
}

# =============================================================================
# Plugin Contract: Render
# =============================================================================

plugin_render() {
    local five_h seven_d
    five_h=$(plugin_data_get "five_h")
    seven_d=$(plugin_data_get "seven_d")
    five_h="${five_h:-0}"
    seven_d="${seven_d:-0}"

    printf '%d%%/%d%%' "$five_h" "$seven_d"
}

# =============================================================================
# Initialize Plugin
# =============================================================================
