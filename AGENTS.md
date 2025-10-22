🧠 Agent Instruction File (agent.md)
📘 Purpose

This file defines the working scope, context, and behavioral rules for the Codex Agent assigned to this repository.
It ensures that all automatic edits, pull requests, and commits follow the correct guidelines and respect all reference materials.

⚙️ General Instructions

The agent is allowed to read all files within this repository to understand structure, dependencies, and logic.

The agent must never copy, extract, or reproduce code or assets from external references or closed-source materials.

All modifications must be original, based on analysis and understanding — not duplication.

📂 Reference Materials

A set of reference ZIP archives is stored in the reference directory.
These archives contain third-party addons and example implementations used only for structural reference.

Important:

These ZIP files may be opened and read by the agent for analysis and understanding purposes,
but their content must never be copied, extracted, or directly reused in this repository.

They are for comparison and understanding only (e.g., how Kaleido or BSC handle certain UI or logic structures).

The agent may reference them conceptually and is allowed to use the same ESO basegame functions as found in these references,
but must rebuild all logic and structure independently using original code.

🧩 Development Guidelines

Follow the ESO Addon API standards and existing patterns within this repository.

Keep all new features modular and localized, so they can be easily toggled or removed.

Prefer clear, maintainable Lua with descriptive naming conventions.

Use English for all code comments, variable names, and debug outputs.

When replicating behavior from another addon (e.g., Kaleido, BSC), do so conceptually, but using the same ESO basegame functions when required.

🧠 Behavior and Commit Policy

Each Pull Request must reference a corresponding GitHub Issue (e.g., Fixes #7).

Commits should have short, descriptive messages (e.g., Add tooltip progress tracking, Fix multi-stage achievement detection).

Debugging code or logs must be flagged or wrapped under a global debug condition.

The agent should always test locally (where possible) before committing.

🚫 Prohibited Actions

❌ Do not copy or reuse code directly from any ZIP file in the reference folder.

❌ Do not extract or import files from those ZIPs into this repository.

❌ Do not fetch external code from the internet without explicit instruction.

❌ Do not overwrite basegame UI functions unless necessary — prefer safe hooks.

✅ Summary

This repository’s agent works under strict compliance with these rules.
The reference archives serve only as design inspiration, not as a codebase source.
All new functionality must be implemented cleanly, safely, and independently,
but may use the same ESO basegame functions as the reference addons when that is the correct or only viable approach.

Last updated: 22.10.2025
