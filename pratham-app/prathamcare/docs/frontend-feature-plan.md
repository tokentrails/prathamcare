# PrathamCare Frontend Feature Plan (Flutter)

## Product decision
- No patient mobile app in MVP.
- Flutter app is for `physician`, `asha_worker`, and clinical admins only.
- Patients receive SMS/email/WhatsApp notifications with secure shareable links for summaries, reports, and lab records.

## Phase 0: App Foundation
- Establish app architecture (`config`, `core`, `data`, `features`).
- Apply brand theme tokens for light/dark.
- Setup shared widgets, app shell, and role dashboard.
- Define environment config for dev/stage/prod.

## Phase 1: Auth + Role Entry
- OTP login flow with Cognito.
- Session persistence in secure storage.
- Role-based landing and navigation guards.

## Phase 2: Doctor + Clinical Worker Core
- Physician dashboard: today schedule, patient queue, alerts.
- ASHA dashboard: assigned tasks, offline capture queue.
- Patient read-only profile/timeline views for staff.

## Phase 2.1: Patient Communication UX (Provider Side)
- Provider action to trigger shareable visit summary/report link.
- Delivery channel selection: SMS, email, WhatsApp.
- Status badges for sent/delivered/failed notifications.

## Phase 3: Voice + Offline
- Voice recording and upload flow.
- Offline queue persistence and retry sync UX.
- Network-aware UX states (offline banners/conflict status).

## Phase 4: Clinical Intelligence UX
- AI patient summary screen.
- Triage result display and physician match UI.
- Patient remarks capture and clinician highlight cards.

## Phase 5: Hardening
- Widget tests for critical paths.
- Accessibility (font scaling, semantic labels, contrast checks).
- Performance tuning for low-end Android devices.
