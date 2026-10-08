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

