# Project Initiation

## Project Name  
`StressApp`

## Target User  
`Apple Watch owners who want an easy, reliable way to monitor and understand their stress level (a feature missing in watchOS by default).`

## Problem / Need  
`The App Store lacks a simple, accurate stress-tracking app for Apple Watch. Garmin users get built-in stress metrics; Apple Watch users do not (or existing solutions are poor or paywalled).`

## Purpose  
`Provide a straightforward, privacy-friendly stress measurement experience on Apple Watch (with an iOS companion), leveraging health data to inform and educate users about their stress patterns.`

## Value Proposition  
`StressApp delivers on-device stress insights based on HealthKit data (e.g., HRV, heart rate). Users can check their current level, review trends over time, and make informed lifestyle adjustments—all without complex dashboards or subscriptions.`

## High-Level Features (MVP)  
- [ ] **Stress Level View** – show current stress level and the raw/derived health values behind it  
- [ ] **Charts & History** – visualize historical stress data (daily/weekly trends)  
- [ ] **Cross-Device Sync** – keep data consistent between Apple Watch and iPhone (WatchConnectivity)

## Technology Stack  
- **Language / Framework:** `Swift + SwiftUI`  
- **APIs:** `HealthKit, WatchConnectivity`  
- **Tools:** `Xcode 15, real device testing, watchOS 10+ / iOS 17+`

## Assumptions  
- `Users grant HealthKit permissions for HRV/heart rate access.`  
- `Basic statistical methods are enough to approximate “stress level” for MVP.`

## Constraints  
- `HealthKit does not offer a direct “stress” metric—must derive it from available signals (e.g., HRV).`  
- `Solo development: limited time → tight MVP scope.`

## Expected Outcome  
`Two companion apps (watchOS + iOS) that:  
- display a derived stress score and contributing metrics,  
- show historical charts,  
- sync data seamlessly between devices.`

## Success Criteria  
- [ ] Builds and runs on both watchOS and iOS real devices  
- [ ] User can record/view a stress measurement on Apple Watch  
- [ ] Basic UI screens for current level + history are implemented  
- [ ] Data is synchronized and consistent across watchOS and iOS apps
