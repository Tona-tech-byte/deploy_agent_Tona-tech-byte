#!/usr/bin/env bash
# Automated Student Attendance Tracker deployment agent

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/templates"

PROJECT_DIR=""
DEPLOYING=false

# ------------------------------------------------------------
# Signal handling
# ------------------------------------------------------------

handle_interrupt() {
    local signal="$1"

    if [ "$DEPLOYING" = true ] && [ -n "$PROJECT_DIR" ]; then
        echo
        echo "=================================================="
        echo "Deployment interrupted by $signal."
        echo "Creating an archive of the incomplete project..."
        echo "=================================================="

        if [ -d "$PROJECT_DIR" ]; then
            local archive="${PROJECT_DIR}_archive.zip"

            rm -f "$archive"

            if zip -rq "$archive" "$PROJECT_DIR"; then
                echo "Incomplete project archived as:"
                echo "$archive"
            else
                echo "ERROR: Failed to create the ZIP archive."
            fi

            rm -rf "$PROJECT_DIR"
            echo "Incomplete project directory removed."
        else
            echo "No project directory existed to archive."
        fi

        DEPLOYING=false
        echo "Deployment session closed cleanly."
        exit 130
    fi
}

trap 'handle_interrupt SIGINT' SIGINT
trap 'handle_interrupt SIGTSTP' SIGTSTP

# ------------------------------------------------------------
# Utility functions
# ------------------------------------------------------------

error_exit() {
    echo "ERROR: $1"
    exit 1
}

check_templates() {
    [ -d "$TEMPLATE_DIR" ] || error_exit "templates/ directory not found."

    [ -f "$TEMPLATE_DIR/attendance_checker.py" ] ||
        error_exit "templates/attendance_checker.py not found."

    [ -f "$TEMPLATE_DIR/assets.csv" ] ||
        error_exit "templates/assets.csv not found."

    [ -f "$TEMPLATE_DIR/config.json" ] ||
        error_exit "templates/config.json not found."
}

preflight_checks() {
    echo
    echo "Running pre-flight checks..."

    if ! command -v python3 >/dev/null 2>&1; then
        error_exit "python3 is not installed or not available in PATH."
    fi

    if ! command -v zip >/dev/null 2>&1; then
        error_exit "zip is not installed or not available in PATH."
    fi

    echo "Python:"
    python3 --version

    echo "zip:"
    zip -v >/dev/null 2>&1 && echo "zip is available."

    check_templates

    echo "Pre-flight checks passed."
}

ask_project_name() {
    local input_name

    while true; do
        read -r -p "Enter a project name suffix: " input_name

        if [[ "$input_name" =~ ^[A-Za-z0-9_-]+$ ]]; then
            break
        fi

        echo "Invalid name. Use only letters, numbers, hyphens, or underscores."
    done

    PROJECT_DIR="$SCRIPT_DIR/attendance_tracker_${input_name}"

    if [ -e "$PROJECT_DIR" ]; then
        echo
        echo "The project already exists:"
        echo "$PROJECT_DIR"

        while true; do
            read -r -p "Overwrite it? (y/n): " overwrite

            case "$overwrite" in
                y|Y)
                    rm -rf "$PROJECT_DIR" ||
                        error_exit "Unable to remove the existing project."
                    break
                    ;;
                n|N)
                    error_exit "Deployment cancelled. Existing project was not changed."
                    ;;
                *)
                    echo "Please enter y or n."
                    ;;
            esac
        done
    fi
}

create_structure() {
    echo
    echo "Creating project structure..."

    DEPLOYING=true

    mkdir -p "$PROJECT_DIR/Helpers" ||
        error_exit "Unable to create Helpers directory."

    mkdir -p "$PROJECT_DIR/reports" ||
        error_exit "Unable to create reports directory."

    mkdir -p "$PROJECT_DIR/archives/attendance" ||
        error_exit "Unable to create attendance archive directory."

    mkdir -p "$PROJECT_DIR/archives/absent" ||
        error_exit "Unable to create absent archive directory."

    echo "Directory structure created."
}

copy_application_files() {
    echo
    echo "Deploying application files..."

    cp "$TEMPLATE_DIR/attendance_checker.py" \
        "$PROJECT_DIR/attendance_checker.py" ||
        error_exit "Failed to deploy attendance_checker.py."

    cp "$TEMPLATE_DIR/config.json" \
        "$PROJECT_DIR/Helpers/config.json" ||
        error_exit "Failed to deploy config.json."

    chmod +x "$PROJECT_DIR/attendance_checker.py" ||
        error_exit "Unable to make attendance_checker.py executable."

    chmod 600 "$PROJECT_DIR/Helpers/config.json" ||
        error_exit "Unable to restrict config.json permissions."

    echo "attendance_checker.py permissions: executable"
    echo "Helpers/config.json permissions: 600 (owner read/write only)"
}

build_roster_from_template() {
    local count
    local available

    available=$(tail -n +2 "$TEMPLATE_DIR/assets.csv" | wc -l)

    while true; do
        read -r -p "How many students should be copied from the template? (1-$available): " count

        if [[ "$count" =~ ^[0-9]+$ ]] &&
           [ "$count" -ge 1 ] &&
           [ "$count" -le "$available" ]; then
            break
        fi

        echo "Please enter a number between 1 and $available."
    done

    {
        head -n 1 "$TEMPLATE_DIR/assets.csv"
        tail -n +2 "$TEMPLATE_DIR/assets.csv" | head -n "$count"
    } > "$PROJECT_DIR/Helpers/assets.csv" ||
        error_exit "Failed to create assets.csv."

    # Template students already have four prior sessions.
    # Therefore config total_sessions remains 5.
    echo "Roster created from template."
    echo "Prior sessions per template student: 4"
    echo "config.json total_sessions: 5"
}

build_fresh_roster() {
    local count
    local i

    local names=(
        "Alice Johnson"
        "Bob Smith"
        "Charlie Brown"
        "Diana Williams"
        "Eric Davis"
        "Faith Miller"
        "Grace Wilson"
        "Henry Moore"
        "Irene Taylor"
        "James Anderson"
    )

    local emails=(
        "alice@example.com"
        "bob@example.com"
        "charlie@example.com"
        "diana@example.com"
        "eric@example.com"
        "faith@example.com"
        "grace@example.com"
        "henry@example.com"
        "irene@example.com"
        "james@example.com"
    )

    while true; do
        read -r -p "How many students should be in the fresh roster? (1-${#names[@]}): " count

        if [[ "$count" =~ ^[0-9]+$ ]] &&
           [ "$count" -ge 1 ] &&
           [ "$count" -le "${#names[@]}" ]; then
            break
        fi

        echo "Please enter a number between 1 and ${#names[@]}."
    done

    echo "Email,Names,Attendance Count,Absence Count" \
        > "$PROJECT_DIR/Helpers/assets.csv" ||
        error_exit "Failed to create assets.csv."

    for ((i=0; i<count; i++)); do
        echo "${emails[$i]},${names[$i]},0,0" \
            >> "$PROJECT_DIR/Helpers/assets.csv" ||
            error_exit "Failed while writing assets.csv."
    done

    # A fresh roster starts at session one.
    # The template's default is 5 because its sample roster has
    # four prior sessions, so update only total_sessions here.
    sed -i -E 's/("total_sessions"[[:space:]]*:[[:space:]]*)[0-9]+/\11/' \
        "$PROJECT_DIR/Helpers/config.json" ||
        error_exit "Failed to set total_sessions to 1."

    echo "Fresh roster created."
    echo "Prior sessions: 0"
    echo "config.json total_sessions: 1"
}

build_roster() {
    echo
    echo "Choose how to build the roster:"
    echo "1) Copy students from templates/assets.csv"
    echo "2) Generate a fresh roster"

    while true; do
        read -r -p "Choose option (1/2): " roster_option

        case "$roster_option" in
            1)
                build_roster_from_template
                break
                ;;
            2)
                build_fresh_roster
                break
                ;;
            *)
                echo "Please choose 1 or 2."
                ;;
        esac
    done
}

valid_percentage() {
    [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 0 ] && [ "$1" -le 100 ]
}

update_thresholds() {
    local answer
    local warning
    local failure

    echo
    read -r -p "Do you want to update the attendance alert thresholds? (y/n): " answer

    case "$answer" in
        y|Y)
            while true; do
                read -r -p "Warning threshold [75]: " warning

                [ -z "$warning" ] && warning=75

                if valid_percentage "$warning"; then
                    break
                fi

                echo "Warning threshold must be a whole number from 0 to 100."
            done

            while true; do
                read -r -p "Failure threshold [50]: " failure

                [ -z "$failure" ] && failure=50

                if valid_percentage "$failure"; then
                    break
                fi

                echo "Failure threshold must be a whole number from 0 to 100."
            done

            sed -i -E \
                "s/(\"warning\"[[:space:]]*:[[:space:]]*)[0-9]+/\1${warning}/" \
                "$PROJECT_DIR/Helpers/config.json" ||
                error_exit "Failed to update warning threshold."

            sed -i -E \
                "s/(\"failure\"[[:space:]]*:[[:space:]]*)[0-9]+/\1${failure}/" \
                "$PROJECT_DIR/Helpers/config.json" ||
                error_exit "Failed to update failure threshold."

            echo "Thresholds updated:"
            echo "  Warning: $warning"
            echo "  Failure: $failure"
            ;;

        n|N)
            echo "Keeping default thresholds."
            ;;

        *)
            echo "Invalid answer. Keeping default thresholds."
            ;;
    esac
}

verify_permissions() {
    echo
    echo "Checking permissions..."

    if [ ! -x "$PROJECT_DIR/attendance_checker.py" ]; then
        error_exit "attendance_checker.py is not executable."
    fi

    if [ "$(stat -c '%a' "$PROJECT_DIR/Helpers/config.json")" != "600" ]; then
        error_exit "config.json does not have permission 600."
    fi

    echo "Permission verification passed."
}

