# Security

## Purpose

This deployment applies basic production hardening suitable for a small web application.

The goal is to reduce common operational risks through:

- restricted network exposure
- strong authentication
- least privilege
- secret management
- encrypted transport
- regular updates
- protected backups
- controlled credentials

This project demonstrates basic hardening only.

It is not a penetration test, vulnerability assessment, or full security audit.

---

## SSH Authentication

Production server access should use SSH key authentication instead of password-based login.

Recommended approach:

```text
developer workstation
        ↓
SSH private key
        ↓
non-root server user
