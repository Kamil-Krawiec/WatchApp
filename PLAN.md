# Project Planning _(v2 – 2025-08-12)_

## 0. What’s New in v2
- **iOS: `Sleep Duration`** in _Latest metrics_ (format: `xh ym` / `--`).
- **iOS: `Sync & Refresh`** – ordering: **`requestCatchUp()` → `reloadSamples()`** (fresher data and more reliable startup).
- **UI:** colored **capsule** for stress category (faster scanning).
- **Cleanup (iOS):** legacy `HealthKitManager` removed on iOS; HealthKit handled on watchOS.

---

## 1. Work Packages & User Stories

### 1.1 User Stories (status @ v2)
- **US-01 — Current stress on Apple Watch:** **Met**  
  Measure on the watch with raw metrics (**HRV ms**, **HR bpm**) and category color.
- **US-02 — History on iPhone:** **Met (MVP)**  
  List / _Latest metrics_ view; **instead of a chart** → a history screenshot:  
  _Screenshot:_ **[iOS — history (7 days)](docs/img/ios_history_7d_v2.png)** ← replace with actual path
- **US-03 — Sync watch ↔ iPhone:** **Met (manual trigger)**  
  iOS `Sync & Refresh`: **`requestCatchUp()` → `reloadSamples()`**; offline retry — **basic** (to verify).

### 1.2 Work Packages (WPs)

| Week | Phase                  | Goal / Focus                                   | Key Tasks & Deliverables                                                                                 | Status               |
|-----:|------------------------|------------------------------------------------|-----------------------------------------------------------------------------------------------------------|----------------------|
| 1    | Planning & Initiating  | Define WHY/WHAT, bootstrap                     | INIT.md & PLAN.md; Xcode projects (watchOS + iOS); user stories & WPs; draft architecture / data flow    | **Done**             |
| 2    | Executing              | Core features (stress calc + watch UI)         | StressCalc (HRV→score); Watch current-stress screen; lightweight local storage                           | **Done**             |
| 3    | Testing & Monitoring   | Validate logic, sync, UX                       | WatchConnectivity; manual QA (permissions, first-launch, no-data); unit consistency & UI responsiveness  | **Done (manual QA)** |
| 4    | Closing (MVP → v2)     | Polish, docs, release                          | iOS: Sleep row; **Sync & Refresh (`catchUp`→`reload`)**; category capsule; README/Docs; tag **v2**       | **Done**             |

> **Note (shared code):** Keep models (`StressSample`, `StressCategory`) in a **single Shared module** with _Target Membership_ enabled for both watchOS and iOS to avoid duplication.

---

## 2. Architecture & Data Flow (v2)

**Layers**
- **Presentation:** SwiftUI (watchOS + iOS)  
- **Domain:** Stress calc (HRV/HR → score/category)  
- **Data:** HealthKit fetchers (watchOS), lightweight local storage, WatchConnectivity (event-driven), iOS “Sync & Refresh”

**High-level flow:**  
HealthKit _(watch)_ → StressCalc → **Local Store (watch)** → WatchConnectivity → **Local Store (iOS)** → iOS UI (_Latest metrics_)

**Sequence (iOS sync – v2)**
~~~mermaid
sequenceDiagram
    participant Watch as watchOS App
    participant WC as WatchConnectivity
    participant iOS as iOS App

    iOS->>Watch: requestCatchUp()   # fetch latest samples from watch
    Watch-->>iOS: latest samples
    iOS->>iOS: reloadSamples()      # update local store + publish UI
~~~

**End-to-end (storage & presentation)**
~~~mermaid
flowchart LR
    HK[(HealthKit HRV, HR)] --> WApp[watchOS App]
    WApp -->|query helpers| Sample["StressSample (date, hrvMs, hrBpm, category)"]
    Sample --> WStore[(Local Store watch JSON)]
    WApp -->|WCSession| Phone[iOS App]
    Phone --> IStore[(Local Store iOS JSON)]
    IStore --> UIiOS["iOS UI Latest metrics: HRV • HR • Sleep • Category capsule"]

~~~

---

## 3. Definition of Done (DoD) — v2

| Area                   | DoD Criteria                                                          | v2 Status                        |
|------------------------|------------------------------------------------------------------------|-----------------------------------|
| Feature Implementation | Acceptance criteria met                                                | **US-01/03 met; US-02 met (MVP)** |
| UI/UX                  | watchOS 10+ / iOS 17+, no clipping; explicit units                    | **OK**                            |
| Data Sync              | Same data on both devices after sync trigger                           | **OK (manual trigger)**           |
| Documentation          | README + INIT + PLAN updated                                           | **OK (PLAN v2)**                  |

---

## 4. Acceptance Criteria (by Story) — with v2 check

**US-01 — Watch (current stress)**
- [x] Tapping “Measure” returns a result in ~< 3 s (typical)
- [x] Error state when HealthKit is denied (verify messaging path)
- [x] Raw metrics visible: **HRV (ms)**, **HR (bpm)** + **category color**

**US-02 — iPhone (history)**
- [x] List / timeline + _Latest metrics_  
- [x] New measurement appears after sync (no app restart)  
- [x] Different time periods accessable

**US-03 — Sync across devices**
- [x] Measurement from watch appears on iPhone within one sync cycle  
- [x] iOS: `Sync & Refresh` = **`requestCatchUp()` → `reloadSamples()`**  
- [] Offline handling not tested

---

## 5. Testing Strategy (v2)

**Manual QA (executed):**
- ✅ HealthKit denied → sensible fallback
- ✅ First-launch / no-data → `--` for Sleep (`formatSleep(_:)`)
- ✅ Sync after relaunch; `catchUp → reload` prevents empty lists on startup

**Devices:** real Apple Watch + iPhone

---

## 6. Release & Versioning
- **Current:** **`v2` – Final app version MVP (2025-08-12)**  
- **Distribution:** local via Xcode  
- **Tags:** `v0.1.0` (MVP), `v1.1.x`, **`v2`**

---

## 7. Communication & Workflow
- **Workflow:** GitHub Issues → feature branches → PR → merge  
- **Docs:** Keep README/INIT/PLAN aligned with release notes  
- **Self-review:** final retro @ v2 (Done / Blocked / Next)

---

## 8. Closure Checklist (final)
- [x] All MVP work packages merged  
- [x] INIT.md success criteria met for MVP scope  
- [x] README/usage + “What’s New in v2” updated  
- [x] Tag **v2** and **close Apple Watch series**

---

## 9. Backlog / De-scoped (future ideas)
- **watch Complication** (category color)
- **watch mini-chart** (last N measurements)
- **iPhone:** full 7-day chart (optional)
- Automated tests for sync & permissions paths
- Battery profiling + debounced auto-updates
