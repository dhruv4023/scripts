#!/usr/bin/env bash
#
#  Git Branch Manager
# -----------------------
# Keeps only the remote-tracking branches you care about:
#   * the latest 3 numeric  releases (e.g. 18.0, 19.0, 20.0) and their saas-X.Y branches
#   * EXCLUDE_BRANCHES base branches (e.g. master)
#   * developer feature branches below those bases ("<base>-...<suffix>"),
#     where <suffix> is any of the developer suffixes you configure (e.g. -djip, -fw)
#
# Safe by design: only local remote-tracking refs are removed.
# Local branches and server branches are never touched.

set -Eeuo pipefail

# ----------------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------------
EXCLUDE_BRANCHES=("master")   # base-branch exceptions (never feature branches)
# Developer suffixes, space separated.
# Priority: env override > suffixes found in current git fetch config > fallback.
# Override: DEFAULT_DEVELOPERS="-abc -xyz" ./script
DEFAULT_DEVELOPERS="${DEFAULT_DEVELOPERS:-}"
FALLBACK_DEVELOPERS="-djip -fw"
LATEST_RELEASE_COUNT=3
MAX_REMOVE_PREVIEW=15

# ----------------------------------------------------------------------------
# UI helpers
# ----------------------------------------------------------------------------
RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
RED=$'\033[38;5;203m'; GREEN=$'\033[38;5;82m'; CYAN=$'\033[38;5;51m'
YELLOW=$'\033[38;5;220m'; WHITE=$'\033[97m'; BG_BLUE=$'\033[48;5;24m'
SPIN_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

info()  { printf '%b•%b %s\n'  "$CYAN"   "$RESET" "$*"; }
ok()    { printf '%b✔%b %s\n'  "$GREEN"  "$RESET" "$*"; }
warn()  { printf '%b⚠%b %s\n'  "$YELLOW" "$RESET" "$*"; }
title() { printf '\n%b%s%b\n' "$BOLD$CYAN" "$*" "$RESET"; }
die()   { printf '%b✘ Error:%b %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

banner() {
    printf '%b╔══════════════════════════════════════════════════════╗%b\n' "$CYAN$BOLD" "$RESET"
    printf '%b║              BRANCH TRACKER CONFIGURATOR             ║%b\n' "$CYAN$BOLD" "$RESET"
    printf '%b╚══════════════════════════════════════════════════════╝%b\n' "$CYAN$BOLD" "$RESET"
}

# Yes/No prompt. Pressing Enter means YES.
confirm() {
    local answer
    printf '%b?%b %s %b[Y/n]%b: ' "$YELLOW" "$RESET" "$1" "$DIM" "$RESET"
    IFS= read -r answer
    [[ -z "$answer" || "$answer" =~ ^[Yy] ]]
}

# Run a command in the background with an animated spinner.
# Usage: spin "message" command [args...]   (output is kept in $SPIN_OUT)
spin() {
    local msg="$1" pid rc=0 i=0 start=$SECONDS
    shift
    SPIN_OUT="$TMP_DIR/spin.out"
    "$@" >"$SPIN_OUT" 2>&1 &
    pid=$!
    printf '\033[?25l'
    while kill -0 "$pid" 2>/dev/null; do
        printf '\r%b%s%b %s %b(%ds)%b\033[K' \
            "$CYAN" "${SPIN_FRAMES[i % ${#SPIN_FRAMES[@]}]}" "$RESET" "$msg" "$DIM" "$((SECONDS - start))" "$RESET"
        i=$((i + 1))
        sleep 0.1
    done
    wait "$pid" || rc=$?
    printf '\033[?25h\r\033[K'
    if ((rc == 0)); then
        printf '%b✔%b %s %b(%ds)%b\n' "$GREEN" "$RESET" "$msg" "$DIM" "$((SECONDS - start))" "$RESET"
    else
        printf '%b✘%b %s\n' "$RED" "$RESET" "$msg"
    fi
    return "$rc"
}

# ----------------------------------------------------------------------------
# Setup
# ----------------------------------------------------------------------------
TMP_DIR="$(mktemp -d)"
cleanup() {
    printf '\033[?25h'
    jobs -p | xargs -r kill 2>/dev/null || true
    rm -rf -- "$TMP_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

declare -a REMOTES=() VERSIONS=() TRACK_BASES=() DEVELOPERS=()
declare -A SELECTED=()

preflight() {
    ((BASH_VERSINFO[0] >= 4)) || die "Bash 4+ is required (found $BASH_VERSION)."
    [[ -t 0 && -t 1 ]] || die "Run this script directly in an interactive terminal."
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "Current directory is not inside a Git repository."

    [[ -z "$(git status --porcelain)" ]] ||
        warn "Working tree has uncommitted changes. They will not be modified."

    if pgrep -af '[g]it (fetch|pull|gc|repack)|[i]ndex-pack|[p]ack-objects' >/dev/null; then
        die "Another Git fetch/gc/repack operation appears to be running."
    fi

    mapfile -t REMOTES < <(git remote)
    ((${#REMOTES[@]} > 0)) || die "No Git remotes are configured."
}

# Fill DEVELOPERS with the suffixes already present in the fetch refspecs,
# e.g. "+refs/heads/19.0-*-djip:refs/remotes/origin/19.0-*-djip" -> "-djip"
detect_configured_developers() {
    local remote spec src rest suffix
    local re='-\*(.+)$'
    local -A seen=()
    DEVELOPERS=()
    for remote in "${REMOTES[@]}"; do
        while IFS= read -r spec; do
            spec="${spec#+}"; src="${spec%%:*}"
            [[ "$src" == refs/heads/* ]] || continue
            rest="${src#refs/heads/}"
            [[ "$rest" =~ $re ]] || continue
            suffix="${BASH_REMATCH[1]}"
            [[ "$suffix" =~ ^[A-Za-z0-9._+@/-]+$ ]] || continue
            [[ -z "${seen[$suffix]:-}" ]] || continue
            seen["$suffix"]=1
            DEVELOPERS+=("$suffix")
        done < <(git config --get-all "remote.$remote.fetch" 2>/dev/null || true)
    done
}

# ----------------------------------------------------------------------------
# Remote scanning (read-only). Produces $TMP_DIR/heads_<i> = branch names.
# ----------------------------------------------------------------------------
scan_remotes() {
    title "Scanning remotes (read-only)"
    local i remote
    for i in "${!REMOTES[@]}"; do
        remote="${REMOTES[$i]}"
        spin "Reading branches from '$remote'" git ls-remote --heads "$remote" ||
            { cat "$SPIN_OUT" >&2; die "Could not scan remote '$remote'. Nothing was changed."; }
        sed -n 's#^[^\t]*\trefs/heads/##p' "$SPIN_OUT" >"$TMP_DIR/heads_$i"
        printf '    %b%s branches found%b\n' "$DIM" "$(wc -l <"$TMP_DIR/heads_$i" | tr -d ' ')" "$RESET"
    done
}

# Runs inside spin() (a background subshell), so it only writes files:
#   $TMP_DIR/all_heads  - every branch name from every remote
#   $TMP_DIR/versions   - selectable release/SaaS branches
discover_versions() {
    local -a releases latest
    local release major start
    cat "$TMP_DIR"/heads_* >"$TMP_DIR/all_heads"

    mapfile -t releases < <(grep -E '^[0-9]+\.0$' "$TMP_DIR/all_heads" | sort -Vu)
    ((${#releases[@]} > 0)) || die "No numeric  release branches (e.g. 20.0) were found."

    start=$((${#releases[@]} > LATEST_RELEASE_COUNT ? ${#releases[@]} - LATEST_RELEASE_COUNT : 0))
    latest=("${releases[@]:start}")

    : >"$TMP_DIR/options"
    for release in "${latest[@]}"; do
        major="${release%%.*}"
        printf '%s\n' "$release" >>"$TMP_DIR/options"
        grep -E "^saas-${major}\.[0-9]+$" "$TMP_DIR/all_heads" >>"$TMP_DIR/options" || true
    done
    sort -Vu "$TMP_DIR/options" >"$TMP_DIR/versions"
    [[ -s "$TMP_DIR/versions" ]] || die "No supported branches were found."
}

# True when a branch (or a feature branch below it) is already covered by an
# existing fetch refspec. Used to pre-select the current configuration.
is_configured() {
    local wanted="$1" remote spec src branch
    for remote in "${REMOTES[@]}"; do
        while IFS= read -r spec; do
            spec="${spec#+}"; src="${spec%%:*}"
            [[ "$src" == refs/heads/* ]] || continue
            [[ "refs/heads/$wanted" == $src ]] && return 0
            while IFS= read -r branch; do
                [[ "$branch" == "$wanted-"* && "refs/heads/$branch" == $src ]] && return 0
            done <"$TMP_DIR/all_heads"
        done < <(git config --get-all "remote.$remote.fetch" 2>/dev/null || true)
    done
    return 1
}

# Runs inside spin(): writes the already-configured versions to $TMP_DIR/preselected.
preselect_versions() {
    local v
    : >"$TMP_DIR/preselected"
    while IFS= read -r v; do
        ! is_configured "$v" || printf '%s\n' "$v" >>"$TMP_DIR/preselected"
    done <"$TMP_DIR/versions"
}

# Load the files produced by the two spinner steps above into the arrays.
load_versions() {
    local v
    mapfile -t VERSIONS <"$TMP_DIR/versions"
    for v in "${VERSIONS[@]}"; do SELECTED["$v"]=0; done
    while IFS= read -r v; do SELECTED["$v"]=1; done <"$TMP_DIR/preselected"
}

# ----------------------------------------------------------------------------
# Interactive selector (draws once, then updates only changed rows)
# ----------------------------------------------------------------------------
ROW_START=7

draw_row() {
    local idx="$1" cursor="$2" v="${VERSIONS[$1]}" mark='[ ]' color="$WHITE"
    [[ "${SELECTED[$v]}" == 1 ]] && { mark='[x]'; color="$GREEN"; }
    printf '\033[%d;1H' "$((ROW_START + idx))"
    if ((idx == cursor)); then
        printf '%b ❯ %s %-36s%b\033[K' "$BG_BLUE$BOLD$WHITE" "$mark" "$v" "$RESET"
    else
        printf '   %b%s %-36s%b\033[K' "$color" "$mark" "$v" "$RESET"
    fi
}

draw_all_rows() { local i; for ((i = 0; i < ${#VERSIONS[@]}; i++)); do draw_row "$i" "$1"; done; }

count_selected() {
    local v n=0
    for v in "${VERSIONS[@]}"; do [[ "${SELECTED[$v]}" == 1 ]] && n=$((n + 1)); done
    printf '%d' "$n"
}

draw_summary() {
    printf '\033[5;1HSelect branches to keep: %b%s / %d selected%b\033[K' \
        "$GREEN" "$(count_selected)" "${#VERSIONS[@]}" "$RESET"
}

draw_status() {   # message line below the help text
    printf '\033[%d;1H%b%s%b\033[K' "$((ROW_START + ${#VERSIONS[@]} + 4))" "$YELLOW" "${1:-}" "$RESET"
}

select_versions() {
    local count="${#VERSIONS[@]}" cursor=0 old key key2 key3 v

    printf '\033[?25l\033[2J\033[H'
    banner
    printf '\n'
    draw_summary
    draw_all_rows "$cursor"
    printf '\033[%d;1H' "$((ROW_START + count + 1))"
    printf '%b↑/↓%b Move   %bSPACE%b Toggle   %ba%b All   %bn%b None\n' \
        "$YELLOW" "$RESET" "$YELLOW" "$RESET" "$YELLOW" "$RESET" "$YELLOW" "$RESET"
    printf '%bENTER%b Continue   %bq%b Quit\n' "$GREEN" "$RESET" "$RED" "$RESET"

    while true; do
        IFS= read -rsn1 key || die "Could not read keyboard input."
        old="$cursor"
        case "$key" in
            $'\x1b')
                key2=''; key3=''
                IFS= read -rsn1 -t 0.15 key2 || true
                [[ "$key2" == '[' || "$key2" == 'O' ]] && { IFS= read -rsn1 -t 0.15 key3 || true; }
                case "$key3" in
                    A) ((cursor > 0)) && cursor=$((cursor - 1)) ;;
                    B) ((cursor < count - 1)) && cursor=$((cursor + 1)) ;;
                esac
                ;;
            ' ')
                v="${VERSIONS[$cursor]}"
                SELECTED["$v"]=$((1 - SELECTED[$v]))
                draw_row "$cursor" "$cursor"; draw_summary; draw_status ""
                ;;
            a|A) for v in "${VERSIONS[@]}"; do SELECTED["$v"]=1; done
                 draw_all_rows "$cursor"; draw_summary; draw_status "" ;;
            n|N) for v in "${VERSIONS[@]}"; do SELECTED["$v"]=0; done
                 draw_all_rows "$cursor"; draw_summary; draw_status "" ;;
            '')
                if (($(count_selected) > 0)); then break; fi
                draw_status "Select at least one branch (SPACE) before continuing."
                ;;
            q|Q) printf '\033[?25h\033[2J\033[H'; info "Cancelled. No changes made."; exit 0 ;;
        esac
        if ((old != cursor)); then draw_row "$old" "$cursor"; draw_row "$cursor" "$cursor"; fi
    done
    printf '\033[?25h\033[2J\033[H'
}

# ----------------------------------------------------------------------------
# Developer suffix editor (multiple suffixes, interactive)
#   type + ENTER  -> add suffix          SPACE      -> continue to next step
#   BACKSPACE     -> delete char / remove last suffix (when input is empty)
#   ↑/↓           -> highlight a suffix  DEL/BACKSPACE on it -> remove it
# ----------------------------------------------------------------------------
DEV_BUF=""        # text currently being typed
DEV_SEL=-1        # highlighted suffix index (-1 = typing in the input line)
DEV_STATUS=""     # one-line feedback message

render_dev_editor() {
    local i n="${#DEVELOPERS[@]}" cols txt
    cols="$(tput cols 2>/dev/null || echo 80)"
    ((cols >= 20)) || cols=80
    local w=$((cols - 2))

    printf '\033[H\033[2J'   # clear fully every frame: no stale/ghost lines
    printf '%bDeveloper branch suffixes%b\n' "$BOLD$CYAN" "$RESET"
    txt='Keeps "<base>-...<suffix>", e.g. 19.0-fix-djip. Case-sensitive, suffix at END.'
    printf '%b%s%b\n\n' "$DIM" "${txt:0:w}" "$RESET"

    printf 'Suffixes (%b%d%b):\n' "$GREEN" "$n" "$RESET"
    if ((n == 0)); then
        printf '  %b(none yet - add at least one)%b\n' "$DIM" "$RESET"
    fi
    for ((i = 0; i < n; i++)); do
        if ((i == DEV_SEL)); then
            printf '%b ❯ %-20s%b %b[DEL] remove%b\n' "$BG_BLUE$BOLD$WHITE" "${DEVELOPERS[$i]}" "$RESET" "$RED" "$RESET"
        else
            printf '   %b• %s%b\n' "$GREEN" "${DEVELOPERS[$i]}" "$RESET"
        fi
    done

    if ((DEV_SEL < 0)); then
        printf '\n%b?%b New suffix: %s%b▏%b\n' "$YELLOW" "$RESET" "$DEV_BUF" "$CYAN" "$RESET"
    else
        printf '\n%b?%b New suffix: %s\n' "$YELLOW" "$RESET" "$DEV_BUF"
    fi

    txt='ENTER add | SPACE continue | BKSP remove last | UP/DOWN+DEL remove'
    printf '\n%b%s%b\n' "$DIM" "${txt:0:w}" "$RESET"
    txt='Ctrl-U clear input | ESC quit'
    printf '%b%s%b\n' "$DIM" "${txt:0:w}" "$RESET"
    [[ -z "$DEV_STATUS" ]] || printf '%b%s%b\n' "$YELLOW" "${DEV_STATUS:0:w}" "$RESET"
}

dev_add() {
    local s="$1" i
    [[ -n "$s" ]] || return 0
    for ((i = 0; i < ${#DEVELOPERS[@]}; i++)); do
        if [[ "${DEVELOPERS[$i]}" == "$s" ]]; then
            DEV_STATUS="'$s' is already in the list."
            return 1
        fi
    done
    DEVELOPERS+=("$s")
    DEV_STATUS="Added '$s'."
    return 0
}

dev_remove() {   # remove index $1
    local idx="$1" removed="${DEVELOPERS[$1]}" n
    unset "DEVELOPERS[$idx]"
    DEVELOPERS=("${DEVELOPERS[@]+"${DEVELOPERS[@]}"}")
    DEV_STATUS="Removed '$removed'."
    n="${#DEVELOPERS[@]}"
    if ((n == 0)); then
        DEV_SEL=-1
    elif ((DEV_SEL >= n)); then
        DEV_SEL=$((n - 1))
    fi
}

edit_developers() {
    local key key2 key3 n re='^[A-Za-z0-9._+@/-]$'

    if [[ -n "$DEFAULT_DEVELOPERS" ]]; then
        read -ra DEVELOPERS <<<"$DEFAULT_DEVELOPERS"
    else
        detect_configured_developers
        if ((${#DEVELOPERS[@]} == 0)); then
            read -ra DEVELOPERS <<<"$FALLBACK_DEVELOPERS"
        fi
    fi
    DEV_BUF=""; DEV_SEL=-1; DEV_STATUS=""

    # Drop any key presses left over from the selector screen.
    while IFS= read -rsn1 -t 0.05 _; do :; done

    printf '\033[?25l\033[2J'
    while true; do
        render_dev_editor
        IFS= read -rsn1 key || die "Could not read keyboard input."
        DEV_STATUS=""
        n="${#DEVELOPERS[@]}"

        case "$key" in
            $'\x1b')
                key2=''; key3=''
                IFS= read -rsn1 -t 0.15 key2 || true
                if [[ -z "$key2" ]]; then   # bare ESC = quit
                    printf '\033[?25h\033[2J\033[H'
                    info "Cancelled. No changes made."
                    exit 0
                fi
                if [[ "$key2" == '[' || "$key2" == 'O' ]]; then
                    IFS= read -rsn1 -t 0.15 key3 || true
                fi
                case "$key3" in
                    A)  # up
                        if ((DEV_SEL < 0)); then
                            ((n == 0)) || DEV_SEL=$((n - 1))
                        elif ((DEV_SEL > 0)); then
                            DEV_SEL=$((DEV_SEL - 1))
                        fi
                        ;;
                    B)  # down (past the last suffix returns to the input line)
                        if ((DEV_SEL >= 0)); then
                            DEV_SEL=$((DEV_SEL + 1))
                            ((DEV_SEL < n)) || DEV_SEL=-1
                        fi
                        ;;
                    3)  # Delete key sends ESC [ 3 ~
                        IFS= read -rsn1 -t 0.15 _ || true
                        if ((DEV_SEL >= 0)); then dev_remove "$DEV_SEL"; fi
                        ;;
                esac
                ;;
            $'\x7f'|$'\b')   # Backspace
                if ((DEV_SEL >= 0)); then
                    dev_remove "$DEV_SEL"
                elif [[ -n "$DEV_BUF" ]]; then
                    DEV_BUF="${DEV_BUF%?}"
                elif ((n > 0)); then
                    dev_remove $((n - 1))
                fi
                ;;
            $'\x15') DEV_BUF="" ;;   # Ctrl-U
            '')                      # Enter = add
                if [[ -n "$DEV_BUF" ]]; then
                    dev_add "$DEV_BUF" || true
                    DEV_BUF=""
                else
                    DEV_STATUS="Type a suffix and press ENTER to add it, or SPACE to continue."
                fi
                DEV_SEL=-1
                ;;
            ' ')                     # Space = continue to next step
                if [[ -n "$DEV_BUF" ]]; then
                    dev_add "$DEV_BUF" || true
                    DEV_BUF=""
                fi
                if ((${#DEVELOPERS[@]} > 0)); then
                    break
                fi
                DEV_STATUS="Add at least one suffix before continuing."
                ;;
            *)
                if [[ "$key" =~ $re ]]; then
                    DEV_BUF+="$key"; DEV_SEL=-1
                else
                    DEV_STATUS="Ignored '$key' (allowed: letters, digits . _ + @ / -)."
                fi
                ;;
        esac
    done
    printf '\033[?25h\033[2J\033[H'
}

# ----------------------------------------------------------------------------
# Plan: which branches to keep per remote
# ----------------------------------------------------------------------------

# True when $1 is a developer branch below base $2 ("<base>-...<suffix>"),
# for any of the configured suffixes.
dev_match() {
    local branch="$1" base="$2" s i
    for ((i = 0; i < ${#DEVELOPERS[@]}; i++)); do
        s="${DEVELOPERS[$i]}"
        [[ "$branch" == "$base"-*"$s" ]] && return 0
        # suffix that starts with "-": also accept "<base><suffix>" (e.g. 19.0-djip)
        [[ "$s" == -* && "$branch" == "$base$s" ]] && return 0
    done
    return 1
}

compute_bases() {
    local v
    TRACK_BASES=("${EXCLUDE_BRANCHES[@]}")
    for v in "${VERSIONS[@]}"; do
        if [[ "${SELECTED[$v]}" == 1 ]]; then TRACK_BASES+=("$v"); fi
    done
}

# Runs inside spin(): writes $TMP_DIR/plan_<i> (branch names) and
# $TMP_DIR/keep_<i> (full remote-tracking ref names) per remote.
build_plan() {
    local i remote branch base
    for i in "${!REMOTES[@]}"; do
        remote="${REMOTES[$i]}"
        : >"$TMP_DIR/plan_$i"
        : >"$TMP_DIR/keep_$i"
        while IFS= read -r branch; do
            for base in "${TRACK_BASES[@]}"; do
                if [[ "$branch" == "$base" ]] || dev_match "$branch" "$base"; then
                    printf '%s\n' "$branch" >>"$TMP_DIR/plan_$i"
                    printf '%s\n' "refs/remotes/$remote/$branch" >>"$TMP_DIR/keep_$i"
                    break
                fi
            done
        done <"$TMP_DIR/heads_$i"
        sort -u -o "$TMP_DIR/plan_$i" "$TMP_DIR/plan_$i"
    done
}

# Runs inside spin(): writes $TMP_DIR/stale_<i> = local remote-tracking refs
# of remote i that are not in its keep list (and are not HEAD).
compute_stale() {
    local i remote ref
    local -A keep=()
    for i in "${!REMOTES[@]}"; do
        remote="${REMOTES[$i]}"
        keep=()
        while IFS= read -r ref; do keep["$ref"]=1; done <"$TMP_DIR/keep_$i"
        : >"$TMP_DIR/stale_$i"
        while IFS= read -r ref; do
            [[ "$ref" == "refs/remotes/$remote/HEAD" ]] && continue
            [[ "${keep[$ref]:-0}" == 1 ]] || printf '%s\n' "$ref" >>"$TMP_DIR/stale_$i"
        done < <(git for-each-ref --format='%(refname)' "refs/remotes/$remote/")
    done
}

# Fetch refspecs for remote index $1, one per line.
#   * exact refspec per base branch that exists on the remote right now
#   * one glob per base and suffix for developer branches ("<base>-*<suffix>")
#   * exact refspec for "<base><suffix>" when the suffix starts with "-"
refspecs_for_remote() {
    local i="$1" remote="${REMOTES[$1]}" base s j

    for base in "${TRACK_BASES[@]}"; do
        if grep -Fqx -- "$base" "$TMP_DIR/heads_$i"; then
            printf '+refs/heads/%s:refs/remotes/%s/%s\n' \
                "$base" "$remote" "$base"
        fi

        for ((j = 0; j < ${#DEVELOPERS[@]}; j++)); do
            s="${DEVELOPERS[$j]}"
            printf '+refs/heads/%s-*%s:refs/remotes/%s/%s-*%s\n' \
                "$base" "$s" "$remote" "$base" "$s"
            if [[ "$s" == -* ]] && grep -Fqx -- "$base$s" "$TMP_DIR/heads_$i"; then
                printf '+refs/heads/%s%s:refs/remotes/%s/%s%s\n' \
                    "$base" "$s" "$remote" "$base" "$s"
            fi
        done
    done | awk '!seen[$0]++'
}

# ----------------------------------------------------------------------------
# Preview
# ----------------------------------------------------------------------------
TOTAL_KEEP=0
TOTAL_REMOVE=0

show_preview() {
    local i remote branch ref v shown n spec
    title "PREVIEW"
    printf 'Selected bases  :'
    for v in "${TRACK_BASES[@]}"; do printf ' %b%s%b' "$GREEN" "$v" "$RESET"; done
    printf '\nDeveloper suffix:'
    for v in "${DEVELOPERS[@]}"; do printf ' %b%s%b' "$GREEN" "$v" "$RESET"; done
    printf '\n'

    for i in "${!REMOTES[@]}"; do
        remote="${REMOTES[$i]}"
        printf '\n%bRemote: %s%b\n' "$BOLD" "$remote" "$RESET"

        while IFS= read -r spec; do
            spec="${spec#+}"
            printf '  %bPATTERN%b %s\n' "$CYAN" "$RESET" "${spec%%:*}"
        done < <(refspecs_for_remote "$i")

        while IFS= read -r branch; do
            [[ -n "$branch" ]] || continue
            printf '  %bKEEP%b    %s\n' "$GREEN" "$RESET" "$branch"
            TOTAL_KEEP=$((TOTAL_KEEP + 1))
        done <"$TMP_DIR/plan_$i"

        shown=0; n=0
        while IFS= read -r ref; do
            n=$((n + 1))
            if ((shown < MAX_REMOVE_PREVIEW)); then
                printf '  %bREMOVE%b  %s %b(local ref only)%b\n' "$YELLOW" "$RESET" "${ref#refs/remotes/$remote/}" "$DIM" "$RESET"
                shown=$((shown + 1))
            fi
        done <"$TMP_DIR/stale_$i"
        ((n <= shown)) || printf '  %b... and %d more local refs%b\n' "$DIM" "$((n - shown))" "$RESET"
        TOTAL_REMOVE=$((TOTAL_REMOVE + n))
    done

    printf '\n%bSummary:%b %d refs kept/fetched, %d local remote-tracking refs removed.\n' \
        "$BOLD" "$RESET" "$TOTAL_KEEP" "$TOTAL_REMOVE"
    printf '%bLocal branches and server branches are NOT deleted. No git gc is run.%b\n\n' "$DIM" "$RESET"
}

# ----------------------------------------------------------------------------
# Apply
# ----------------------------------------------------------------------------
restore_fetch_config() {
    local i remote spec
    for i in "${!REMOTES[@]}"; do
        remote="${REMOTES[$i]}"
        git config --unset-all "remote.$remote.fetch" 2>/dev/null || true
        while IFS= read -r spec; do
            [[ -z "$spec" ]] || git config --add "remote.$remote.fetch" "$spec"
        done <"$TMP_DIR/old_fetch_$i"
    done
}

apply_plan() {
    local i remote spec ref removed=0
    local -a stale

    title "Applying plan"

    # 1. Back up + rewrite fetch refspecs
    for i in "${!REMOTES[@]}"; do
        git config --get-all "remote.${REMOTES[$i]}.fetch" >"$TMP_DIR/old_fetch_$i" || true
    done
    for i in "${!REMOTES[@]}"; do
        remote="${REMOTES[$i]}"
        git config --unset-all "remote.$remote.fetch" 2>/dev/null || true
        while IFS= read -r spec; do
            git config --add "remote.$remote.fetch" "$spec"
        done < <(refspecs_for_remote "$i")
        git config "remote.$remote.prune" true          # drop refs of branches deleted on the server
        git config "remote.$remote.tagOpt" --no-tags
    done
    ok "Fetch patterns saved (future 'git fetch' / 'git remote update' follow them)"

    # 2. Fetch everything before deleting anything
    for i in "${!REMOTES[@]}"; do
        remote="${REMOTES[$i]}"
        if ! spin "Fetching tracked branches from '$remote'" \
                git fetch --prune --no-tags "$remote"; then
            cat "$SPIN_OUT" >&2
            restore_fetch_config
            warn "Previous fetch configuration restored."
            die "Fetch failed. Existing remote-tracking refs have not been cleaned."
        fi
    done

    # 3. Remove unselected remote-tracking refs (with live progress)
    for i in "${!REMOTES[@]}"; do
        mapfile -t stale <"$TMP_DIR/stale_$i"
        for ref in "${stale[@]+"${stale[@]}"}"; do
            [[ -n "$ref" ]] || continue
            git update-ref -d "$ref"
            removed=$((removed + 1))
            printf '\r%b⠿%b Cleaning local remote-tracking refs: %d / %d\033[K' "$CYAN" "$RESET" "$removed" "$TOTAL_REMOVE"
        done
    done
    printf '\r\033[K'
    ok "Removed $removed unselected remote-tracking refs"

    printf '\n%b✔ Done.%b Kept/fetched %d branch refs, removed %d refs.\n' "$GREEN$BOLD" "$RESET" "$TOTAL_KEEP" "$removed"
    printf '%bRun "git branch -vv" to review local branch upstream status.%b\n' "$DIM" "$RESET"
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
    banner
    preflight
    info "Repository: $(git rev-parse --show-toplevel)"
    info "Remotes   : ${REMOTES[*]}"

    scan_remotes
    spin "Detecting latest release & SaaS branches" discover_versions ||
        { cat "$SPIN_OUT" >&2; die "Could not build the branch list."; }
    spin "Checking current fetch configuration" preselect_versions ||
        { cat "$SPIN_OUT" >&2; die "Could not read the current fetch configuration."; }
    load_versions
    ok "Found ${#VERSIONS[@]} selectable branches"
    sleep 0.4

    select_versions
    edit_developers
    compute_bases
    spin "Building branch plan" build_plan ||
        { cat "$SPIN_OUT" >&2; die "Could not build the plan. Nothing was changed."; }
    spin "Preparing preview (scanning local refs)" compute_stale ||
        { cat "$SPIN_OUT" >&2; die "Could not prepare the preview. Nothing was changed."; }
    show_preview

    confirm "Apply this plan?" || { info "Cancelled. No changes made."; exit 0; }
    apply_plan
}

main "$@"
