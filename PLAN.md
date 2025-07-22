# Project Planning

---

## 1. Work Packages & User Stories

### 1.1 User Stories
- US-01: As a user, I want to see my current stress level on Apple Watch, so I can quickly assess how I feel.
- US-02: As a user, I want to view a history chart on iPhone, so I can track trends over time.
- US-03: As a user, I want my data synced between watch and phone, so I never lose measurements.

### 1.2 Work Packages (WPs)
| Week | Phase                          | Goal / Focus                                   | Key Tasks & Deliverables                                                                 | Status        |
|------|--------------------------------|------------------------------------------------|-------------------------------------------------------------------------------------------|---------------|
| 1    | Planning & Initiating (NOW)    | Define WHY/WHAT and set up the project         | • Finalize INIT.md & PLAN.md<br>• Create Xcode projects (watchOS + iOS)<br>• Draft user stories & WPs<br>• Outline architecture & data flow | ☐ Not started |
| 2    | Executing                      | Build core features (stress calc + watch UI)   | • Implement StressCalc module (HRV → score)<br>• Build Watch current-stress screen<br>• Set up local storage layer | ☐ Not started |
| 3    | Testing & Monitoring           | Validate logic, sync, and UX                   | • Implement sync via WatchConnectivity<br>• Unit/integration tests (calc, sync)<br>• Manual QA checklist run | ☐ Not started |
| 4    | Closing                        | Polish, document, and wrap MVP                  | • Fix bugs & UI polish<br>• Update README/Docs (usage, lessons learned)<br>• Tag release v0.1.0 | ☐ Not started |

---

## 2. Architecture & Data Flow

- **Layers:**  
  - Presentation: SwiftUI views on watchOS & iOS  
  - Domain: Stress calculation (HRV, heart rate → score)  
  - Data: HealthKit fetchers, local store, sync bridge  

- **Data Flow:** HealthKit → StressCalc → Local Store → Sync → UI

---

## 3. Definition of Done (DoD)

| Area                 | DoD Criteria                                                                 |
|----------------------|-------------------------------------------------------------------------------|
| Feature Implementation | Acceptance criteria met                             |
| UI/UX                | Works on watchOS 10+ & iOS 17+, no clipping/layout issues                     |
| Data Sync            | Same data visible on both devices after sync trigger                          |
| Documentation        | README + INIT + PLAN updated                                                  |

---

## 4. Acceptance Criteria (per Story)

**US-01 (Current stress on Watch):**  
- [ ] Tapping “Measure” returns a stress value in <3s  
- [ ] Error messaging for HealthKit denial  
- [ ] Raw metrics (e.g., HRV) accessible/visible via UI

**US-02 (History on iPhone):**  
- [ ] Chart shows last 7 days minimum  
- [ ] List view scrollable with timestamps  
- [ ] New measurement appears after sync without app restart

**US-03 (Sync across devices):**  
- [ ] Measurement on watch appears on iPhone within one sync cycle  
- [ ] Offline handling: data queued and sent when connectivity resumes

---

## 5. Testing Strategy

- **Manual QA Checklist:**  
  - Permission denied scenario  
  - First-launch with no data  
  - Airplane mode sync retry  
- **Tools:** real Apple Watch + iPhone

---

## 6. Release & Versioning

- **Version:** `v0.1.0` for MVP  
- **Distribution:** Local via Xcode 
- **Git:** Tag releases (`v0.1.0`, `v0.2.0`, ...)

---

## 7. Communication & Workflow

- **Workflow:** GitHub Issues → Feature branches → PR → Merge  
- **Docs:** Update INIT/PLAN when scope or architecture shifts  
- **Self Review:** Weekly mini-retro: Done / Blocked / Next

---

## 8. Closure Checklist (preview)

- [ ] All WPs complete & checked in  
- [ ] Success criteria from INIT.md met  
- [ ] README usage section written  

---
