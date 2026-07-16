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

## What's included

- Employee master (manual entry + bulk CSV import/export, template provided
  in-app)
- Monthly attendance entry (manual grid + CSV import) driving pro-rated pay
- Payroll run: preview → save as draft → admin finalizes (locks it)
- Payslip view/print (browser print-to-PDF)
- PF challan, ESI, and Professional Tax reports, each exportable as CSV
- Settings page for PF rate/ceiling, ESI rate/ceiling, and AP PT slabs —
  editable in case the state revises them

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
