# Friends School Payroll

A single-file HTML app (like Campus Stock) backed by Supabase — payroll for
Friends Vidyanikethan School: employee master, attendance-based deductions,
PF, ESI, Andhra Pradesh Professional Tax, payslips, and statutory reports.

## 1. Set up Supabase

1. Go to your Supabase project (same one as Campus Stock, or a new project —
   recommend a **separate** project since this holds salary data).
2. **SQL Editor → New Query** → paste the contents of `schema.sql` → Run.
   This creates all tables, default settings (PF/ESI/AP-PT rates), and
   Row Level Security policies.
3. **SQL Editor → New Query** → paste the contents of
   `schema_update_employee_portal.sql` → Run. This adds employee
   self-service logins, twice-daily geo-tagged attendance, and tightens RLS
   so an employee login can never see another staff member's salary data.
4. **SQL Editor → New Query** → paste `schema_update_leave_management.sql`
   → Run. Adds the Leave Management module (leave types, balances, requests)
   and auto-generates Employee Codes as `FVN-EMP-001`, `FVN-EMP-002`, ...
5. **SQL Editor → New Query** → paste `schema_update_phase1.sql` → Run.
   Adds Left/Terminated employee status, check-out time + working hours on
   attendance, and the late-entry cutoff setting.
6. **SQL Editor → New Query** → paste `schema_update_phase2.sql` → Run.
   Adds the Holiday Calendar and in-app notifications.
7. **SQL Editor → New Query** → paste `schema_update_phase2b.sql` → Run.
   Adds attendance backfill requests, default Sunday/2nd-Saturday holidays,
   and removes the automatic CL grace.
8. **SQL Editor → New Query** → paste `schema_update_phase2c.sql` → Run.
   Adds the `arrears` table so backfilled attendance for an already-
   finalized month automatically flows into the next payroll run.
4. **Authentication → Providers** → make sure Email is enabled. If you want
   staff to start marking attendance immediately after signing up (no email
   click needed), turn **off** "Confirm email" under Authentication →
   Providers → Email — otherwise they'll need to confirm via email link
   before their first sign-in.
5. **Authentication → Users → Add user** to create your first login
   (e.g. yourself as admin).
6. After creating that user, go to **Table Editor → profiles**, find the row
   for that user, and change `role` from `viewer` to `admin`. Every new
   signup defaults to `viewer` — only an admin can promote others (also via
   the `profiles` table for now; a settings-page role manager can be added
   later if useful).
7. **Project Settings → API** → copy your **Project URL** and **anon public
   key**.

## 2. Configure the app

Open `index.html` and edit these two lines near the top of the `<script>`:

```js
const SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-PUBLIC-KEY';
```

## 3. Deploy (same pipeline as Campus Stock)

Push `index.html` (and `manifest.json`) to a GitHub repo and deploy via the
GitHub Actions static HTML workflow — the same approach already working for
Campus Stock, to avoid the branch-deploy file-conflict issue you hit before.

## Roles

- **admin** — everything, including Settings (PF/ESI/PT rates) and
  finalizing payroll runs
- **accountant** — manage employees, attendance, run payroll, view/print
  payslips and reports (cannot edit statutory settings or finalize a run)
- **viewer** — read-only: can see payslips and reports, nothing else
- **employee** — self-service only: mark their own morning/afternoon
  attendance, see their own attendance history, view their own finalized
  payslips. An employee login can never query another staff member's salary,
  bank details, or PAN — this is enforced at the database level (RLS), not
  just hidden in the UI.

## Employee self-service attendance

1. The school office first creates the employee's record as usual (Employees
   tab), which gives them an **Employee Code**.
2. The staff member opens the app, clicks **"Create your account"** on the
   sign-in screen, and enters that Employee Code + their own email/password.
   This links their login to their employee record and switches their role
   to `employee` automatically.
3. Each day they open **Mark Attendance** and tap the morning and afternoon
   buttons. Marking requires granting the browser location permission — the
   coordinates are stored with every mark. If you configure a school
   location + radius in **Settings → Attendance Location**, marks made
   outside that radius are rejected; if you leave it off, location is still
   recorded but not enforced.
4. If a session isn't marked, it counts as unmarked for that half of the
   day — one missed session = half-day absent, both missed = full-day
   absent.
5. Each month, absences are covered first by **Casual Leave** (2 per month
   by default, configurable in Settings → Leave Policy) with no pay cut;
   anything beyond that becomes **Loss of Pay**.
6. On the admin side, the **Attendance** tab has a **"Sync from
   Self-Attendance"** button that pulls this calculation in for review —
   the office can still adjust any row by hand before saving, so self-marked
   attendance is a starting point, not an unchangeable record.
7. Employees only ever see their own **finalized** payslips — draft runs
   (which might still change) stay hidden from self-service view.

## Bug fixes (no schema change needed — index.html only)

- **Timezone date-shift bug**: several places built a "YYYY-MM-DD" string
  from a local Date using `.toISOString()`, which converts to UTC first.
  In India (UTC+5:30) this silently shifted dates back by a day — most
  visibly in "Find Missing Days" for Attendance Backfill, where the whole
  requested range could shift by one day (e.g. asking for Jul 1–16 could
  show Jun 30 and miss Jul 16 entirely). Fixed by adding a `localDateStr()`
  helper that reads local year/month/day components instead, and using it
  everywhere a date-only string is derived from a Date object.
- **Finalized payroll + backfill approval**: approving an attendance
  backfill request no longer silently does nothing to a payslip that's
  already been finalized. The Attendance Backfill screen now flags any
  request whose date falls in an already-finalized month — approving it
  automatically queues an **arrear** that flows into the employee's next
  payroll run (see below). The historical payslip itself is never
  automatically rewritten.

## Follow-up fixes (this update)

- **Finalized runs are now locked from silent overwrite.** Previously,
  clicking "Save as Draft" would upsert over a run even if it was already
  finalized — so re-previewing a finalized month and saving again could
  silently do nothing useful (or worse, look like it worked). Now saving
  is blocked with a clear message if the selected month is finalized —
  arrears for that employee will instead be picked up the next time you
  run a **later** month.
- **Pending Arrears Queue** now shows on the Payroll Run page at all times
  — who's owed what and why, before you even pick a month — so there's no
  more guessing about whether an arrear was actually created or which
  month it'll land in.
- **Attendance grid no longer silently goes stale.** Previously, once a
  month's attendance was saved, the grid always showed those saved values
  even if self-attendance changed afterward (e.g. a backfill approved
  later) — you had to remember to click "Sync from Self-Attendance" to
  notice. Now each row is checked against current self-attendance on load;
  if they've diverged, a **⚠ Refresh** button appears on that row showing
  what the new numbers would be. It only refreshes that one row when
  clicked — nothing is overwritten automatically, so any manual admin
  edits you made are never silently discarded.

## Do the .sql files need to go in the GitHub repo?

No — GitHub Pages only serves static files to the browser (`index.html`,
`manifest.json`); it never executes `.sql` files, so they're not required
for the app to run. Every `schema*.sql` file is meant to be run **once,
manually, in Supabase's SQL Editor** — never automatically. That said, it's
good practice to keep them committed in the repo anyway, purely as a
version history of your database schema (so anyone can see what changed
and when) — just don't expect uploading them to *do* anything on their own.

## Where arrears actually land — a timing note

An arrear queued today is picked up by whichever payroll month you next
**preview and save**, not necessarily the very next calendar month. If
that next month happens to already be finalized by the time you approve
the backfill, the arrear rolls forward again to the month after that. The
Pending Arrears Queue (above) is the reliable way to check whether an
arrear was actually created and is still waiting — if a payroll month
"isn't showing more," check there first, and also confirm this file and
`schema_update_phase2c.sql` are actually the versions currently deployed
and run in Supabase.

## This update

- **Reopening a finalized payroll run** was already built (you may not have
  noticed it): on the Payslips page, a finalized run shows a **"Reopen for
  Editing"** button (admin only) that sets it back to draft so you can
  re-run Payroll Run and save again.
- **Reconcile Arrears** tool (was referenced in a warning message but not
  actually built until now — fixed): on the Payroll Run page, click
  "Reconcile Arrears" to see every arrear ever created, whatever its
  status, and manually mark one applied/pending/cancelled. This is the fix
  for an arrear reappearing at the same amount every month.
- **Found the likely cause of the repeating arrear**: Postgres/Supabase
  doesn't return an error when an UPDATE matches zero rows (e.g. blocked by
  a permissions policy) — it just silently updates nothing. So the
  "mark this arrear as applied" step could fail invisibly, leaving the
  arrear "pending" forever and getting re-added to every subsequent
  month's payroll. The save flow now checks the actual number of rows
  updated (not just "was there an error"), and warns loudly if it doesn't
  match — pointing you at Reconcile Arrears to fix it by hand.
- **Reports now has separate Month + Year selectors** (matching Payroll
  Run), instead of one combined "pick a run" dropdown.
- **Financial Year is now June–May**, not calendar year. Leave balances,
  entitlements, and the admin balance editor all key off FY (e.g. "FY
  2026-27" = June 2026 through May 2027) instead of Jan–Dec.
- **Backfill requests now support Half Day / Full Day** per date, in the
  same tabular missing-days form — Half Day credits one session (0.5 day,
  matching how half-days work everywhere else in the app); Full Day
  credits both. Arrears calculated from a half-day backfill are correctly
  half the per-diem rate.
- **`reset_test_data.sql`** — an optional, clearly-marked-destructive
  script to wipe all attendance/leave/payroll/payslip/arrears/notification
  data while keeping employees and settings intact, so you can test the
  whole flow from a clean slate. Doesn't touch employees or their logins
  unless you deliberately uncomment the extra section at the bottom.

## Backfill → Arrears (automatic)

Approving an attendance backfill for a date whose payroll month is already
**finalized** never rewrites that old payslip. Instead it now automatically:

1. Looks up that employee's finalized payslip for the original month and
   works out a fair per-day rate (that month's gross ÷ days in month)
2. Queues an **arrear** for that amount
3. Pulls it into the employee's **next** payroll run automatically — shown
   as its own "Arrears" column in the run preview, and its own line on the
   printed payslip (with the reason, e.g. which date/month it's for)
4. Marks the arrear as applied once that run is saved, so it's never paid
   out twice

This is a same-gross-rate approximation — it doesn't re-run PF/ESI/PT for
the corrected month, just adds the missing day's gross pay to the next
payslip. That's usually fine for one or two missed days; if you're
backfilling many days in a finalized month, or the correction pushes PF/ESI
near a wage-ceiling boundary, it's worth sanity-checking the numbers by
hand.

## What's included

- Employee master (manual entry + bulk CSV import/export, template provided
  in-app) — **Employee Code is now auto-generated** (`FVN-EMP-001`,
  `FVN-EMP-002`, ...) and read-only after creation
- Employee status now includes **Left** and **Terminated** (with a Last
  Working Day field), in addition to Active/Inactive
- Named salary components — add as many as you like (e.g. "Tuition Salary",
  "Special Allowance") instead of one lump "other allowances" figure
- Monthly attendance entry (manual grid + CSV import) driving pro-rated pay,
  now auto-populated from employee self-marked attendance by default (no
  longer defaults to full-pay before syncing)
- Employee self-service: create account via Employee Code, mark morning/
  afternoon **check-in and check-out** with geo-tagging, see working hours
  and a late-entry flag
- **Leave Management module**: employees apply for CL/SL/EL/Maternity/
  Paternity/Comp-Off/LWP with from-to dates and a reason; admins approve/
  reject with comments, view/edit balances, and export a Leave Register.
  Approved leave automatically feeds into the attendance/LOP calculation
- Payroll run: preview → save as draft → admin finalizes (locks it)
- Payslip view/print (browser print-to-PDF)
- **Salary Register** report with full PF/ESI/PT/net breakdown and bank
  details, a **Management report** (department-wise totals), plus the PF
  challan, ESI, and Professional Tax reports — all exportable as CSV
- Settings page for PF rate/ceiling, ESI rate/ceiling, AP PT slabs, leave
  entitlements, the monthly CL grace fallback, and attendance rules
  (late-entry cutoff)
- Auto-refresh every 45s on Dashboard, Leave Requests, and Mark Attendance
  (skipped on editable grids like Attendance/Payroll Run so in-progress
  edits are never wiped)
- **Holiday Calendar** (national/state/school/optional) — holidays never
  count as absent, anywhere in the app
- **Attendance calendar views** — employees see a color-coded monthly
  calendar in My Attendance History; admins can pull up any employee's
  calendar from the Attendance page
- **Dashboard**: Present Today, Employees Absent Today, Pending Leave
  Requests, and a **This Week — Missing Attendance** widget (days with no
  check-in, no approved leave, no holiday, Monday through today)
- **In-app notifications** (bell icon, top right) for leave approval/
  rejection and payslip availability — polls every 60s

## Note on the "Saturday weekly summary"

There's no server-side scheduler here (GitHub Pages is static hosting — no
cron). Instead, the **Missing Attendance** widget on the Dashboard computes
live, any day of the week, showing Monday-through-today gaps — so checking
it on Saturday still gives you the full week's picture. If you want a true
scheduled job (e.g. an automatic email every Saturday morning), that needs
a small serverless function (Supabase Edge Functions + `pg_cron`, or a
GitHub Actions scheduled workflow) — happy to add that as a follow-up.

## Deferred to a later phase (by request, to avoid shipping shallow features)

- **Year-wise salary increment** tracking (% or amount) with history
- **Multi-level approval chains** (Reporting Manager → Principal →
  Management for payroll; Employee → Manager → Admin for leave) — current
  version has single-level approval by any admin/accountant
- Extra employee profile fields (Aadhaar, UAN, ESI number, photo, DOB,
  gender, blood group, emergency contact, qualifications, reporting manager)
- Bonus/incentive/arrears/overtime/loan-recovery/salary-advance payroll
  components
- Birthday and document-expiry notifications (need the profile fields
  above first)
- Two-factor authentication, audit log, login history
- True scheduled weekly summary (see note above — needs a serverless
  function, not just app code)

## What's intentionally left out (per your call)

- **TDS (income tax) auto-calculation** — skipped for now. Track manually
  via your existing Form 16 process, or come back later to add it (it needs
  each employee's tax regime choice and investment declarations to be
  accurate).
- PF and ESI are applied **per employee**, using the checkboxes on each
  employee's record — so you can mark individuals as exempt without
  changing school-wide settings.

## Known simplifications to revisit

- Professional Tax slabs are seeded with the current AP rates (₹0 up to
  ₹15,000; ₹150 for ₹15,001–20,000; ₹200 above that, ₹300 in March, capped
  ₹2,500/year) — these are editable in Settings since states revise them
  periodically; double-check against the AP Commercial Taxes Department
  before your first real run.
- No leave-type breakdown (casual/sick/earned) yet — attendance is just
  paid days vs. total days. Can be extended later if you track leave types
  separately.
- Role management (promoting a user to admin/accountant) is done directly
  in the Supabase Table Editor for now rather than an in-app screen.
