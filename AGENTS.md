# 🧠 Agent Instruction File (`AGENTS.md`)

## 📘 Purpose
This file defines the working scope, context, and behavioral rules for the Codex Agent assigned to this repository.
It ensures that all automatic edits, pull requests, and commits follow the correct guidelines and respect all reference materials.

---

## ⚙️ General Instructions
- The agent is **allowed to read all files** within this repository to understand structure, dependencies, and logic.
- The agent must **never copy, extract, or reproduce** code or assets from external references or closed-source materials.
- All modifications must be **original**, based on analysis and understanding — not duplication.

---

## 📂 Reference Materials
A set of **reference ZIP archives** is stored in the `reference` directory.
These archives contain **third-party addons and example implementations** used *only for structural reference*.

**Important:**
- These ZIP files **may be opened and read** by the agent for analysis and understanding purposes,
  but their content **must never be copied, extracted, or directly reused** in this repository.
- The agent may **open and inspect** files inside the reference ZIP archives to analyze how functions or UI structures are implemented.
  This includes **syntax inspection and code comparison for understanding**, but the agent must **never copy, extract, or reuse** any part of that code.
- They are **for comparison and understanding only** (e.g., how Kaleido or BSC handle certain UI or logic structures).
- The agent may reference them conceptually and is **allowed to use the same ESO basegame functions** as found in these references,
  but must **rebuild all logic and structure independently** using original code.
- The agent is **explicitly allowed to use the official ESO API documentation, TXT dump files, and the ESO Wiki** for reference and verification.
  When doing so, it must always ensure that it references **the most recent game version** and avoids outdated or deprecated API calls.

---

## 🧩 Development Guidelines
- Follow the **ESO Addon API standards** and existing patterns within this repository.
- Keep all new features **modular and localized**, so they can be easily toggled or removed.
- Prefer **clear, maintainable Lua** with descriptive naming conventions.
- Use English for all code comments, variable names, and debug outputs.
- When replicating behavior from another addon (e.g., *Kaleido*, *BSC*), do so **conceptually**, but using the same ESO basegame functions when required.
- When relying on ESO API data, the agent must **verify compatibility with the latest API version** and **log deprecated usages** if encountered.
- **The agent may create new functions using the same ESO basegame APIs, events, and UI resources as seen in reference addons, as long as all logic and implementation are written independently.**
- **Changes may span multiple addon files** (init, scenes/fragments, XML templates, LAM, SavedVars) **if required** to attach to HUD/HUDUI scenes, manage default tracker visibility, or persist tracker state. Keep the implementation modular.
- The agent **may create/attach fragments to HUD/HUDUI scenes** and adjust anchors/parents to match base tracker behavior (show/hide on scene changes, combat hide, locking), using original code.

---

### Function Namespace Rule (ESOUI Compliance)

All addon functions must be defined under the global addon table `Nvk3UT` and **never** as standalone global functions.

**Allowed:**
```lua
function Nvk3UT.DoSomething(...)
    ...
end

Not allowed:

function Nvk3UT_DoSomething(...)
    ...
end
```

### unpack() Usage Rule

The addon must **not** redefine or wrap `unpack`. We always use the built-in function provided by the ESO Lua runtime.

**Allowed:**
```lua
local a, b, c = unpack(someTable)

Not allowed:

local fn_unpack = _G["unpack"] or table.unpack
local unpack = table.unpack or unpack
-- or any other custom alias/wrapper

Reason:

Avoids shadowing the global unpack function.

Prevents subtle bugs when different modules try to be "compatible".

Keeps the code consistent and easier to debug.

ESO’s Lua runtime already provides a working unpack(), so no compatibility layer is needed.

Going forward, any new code that needs to expand tables must directly call unpack(...) (or table.unpack(...) only in exceptional cases, with a comment explaining why).
```

---

## 🧠 Behavior and Commit Policy
- Each Pull Request must reference a corresponding GitHub Issue (e.g., `Fixes #7`).
- Commits should have **short, descriptive messages** (e.g., `Add tooltip progress tracking`, `Fix multi-stage achievement detection`).
- Debugging code or logs must be **flagged or wrapped** under a global debug condition.
- The agent should always **test locally** (where possible) before committing.

---

## ⚙️ Configuration & Support Files
- [`.editorconfig`](.editorconfig): shared text editor defaults for the project.
- [`tools/`](tools/): helper scripts related to packaging or distribution.

---

## 🚫 Prohibited Actions
- ❌ Do **not** copy or reuse code directly from any ZIP file in the `reference` folder.
- ❌ Do **not** extract or import files from those ZIPs into this repository.
- ❌ Do **not** fetch external code from the internet without explicit instruction.
- ❌ Prefer safe hooks (ZO_PreHook/ZO_PostHook). However, when functional parity with the base tracker requires it, the agent **may override or replace** specific basegame handlers (e.g., default tracker visibility/fragment wiring). Such overrides must be minimal, documented, and limited in scope.

---

## ✅ Summary
This repository’s agent works under strict compliance with these rules.
The `reference` archives serve **only** as design inspiration, not as a codebase source.
All new functionality must be implemented cleanly, safely, and independently,
but may use the same ESO basegame functions as the reference addons when that is the correct or only viable approach.
The agent may freely use the **ESO API, TXT dumps, and Wiki** for accurate and up-to-date information.
When in doubt, **functional parity with the base tracker** takes precedence over cosmetic similarity, provided all code remains original and compliant with ESO API.

---

_Last updated: 23.10.2025_
