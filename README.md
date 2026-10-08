# deploy_agent_Tona-tech-byte

## Project Overview

This project is an automated deployment agent for a Student Attendance Tracker application.

The deployment agent is written in Bash and automates the setup, configuration, execution, and log archiving of the attendance application.

The project demonstrates:

- Bash scripting
- Automation and reproducibility
- File and directory management
- Configuration management
- Process management
- Signal handling
- Permissions management
- Log archiving
- Git version control

---

## Requirements

The deployment agent requires:

- Linux environment
- Bash
- Python 3
- zip
- ShellCheck
- Git

The script performs preflight checks for `python3` and `zip` before deployment begins.

---

## Repository Structure

```text
deploy_agent_Tona-tech-byte/
├── deploy_agent.sh
├── README.md
└── templates/
    ├── attendance_checker.py
    ├── assets.csv
    └── config.json
