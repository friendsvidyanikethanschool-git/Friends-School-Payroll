-- ============================================================================
-- Friends School Payroll — Supabase Schema
-- Run this once in Supabase SQL Editor (Project → SQL Editor → New Query)
-- ============================================================================

-- ---------- 1. PROFILES (roles layered on top of Supabase Auth) ----------
create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'viewer' check (role in ('admin','accountant','viewer')),
  created_at timestamptz default now()
);

-- Auto-create a profile row whenever a new auth user signs up
create or replace function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, new.raw_user_meta_data->>'full_name', 'viewer');
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

-- ---------- 2. EMPLOYEES ----------
create table if not exists employees (
  id uuid primary key default gen_random_uuid(),
  emp_code text unique not null,
  full_name text not null,
  designation text,
  department text,
  date_of_joining date,
  status text not null default 'active' check (status in ('active','inactive')),
  bank_name text,
  bank_account_no text,
  ifsc_code text,
  pan_no text,
  phone text,
  basic numeric(12,2) not null default 0,
  hra numeric(12,2) not null default 0,
  allowances jsonb not null default '{}'::jsonb, -- e.g. {"conveyance":1000,"medical":500}
  pf_applicable boolean not null default true,
  esi_applicable boolean not null default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- ---------- 3. ATTENDANCE (per employee, per month) ----------
create table if not exists attendance (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  month int not null check (month between 1 and 12),
  year int not null,
  total_days int not null default 30,
  paid_days numeric(5,2) not null default 30,
  lop_days numeric(5,2) not null default 0,
  remarks text,
  created_at timestamptz default now(),
  unique (employee_id, month, year)
);

-- ---------- 4. PAYROLL RUNS ----------
create table if not exists payroll_runs (
  id uuid primary key default gen_random_uuid(),
  month int not null check (month between 1 and 12),
  year int not null,
  status text not null default 'draft' check (status in ('draft','finalized')),
  created_by uuid references profiles(id),
  finalized_at timestamptz,
  created_at timestamptz default now(),
  unique (month, year)
);

-- ---------- 5. PAYSLIPS (one row per employee per run) ----------
create table if not exists payslips (
  id uuid primary key default gen_random_uuid(),
  payroll_run_id uuid not null references payroll_runs(id) on delete cascade,
  employee_id uuid not null references employees(id),
  gross numeric(12,2) not null,
  earned_gross numeric(12,2) not null,
  pf_employee numeric(12,2) not null default 0,
  pf_employer numeric(12,2) not null default 0,
  esi_employee numeric(12,2) not null default 0,
  esi_employer numeric(12,2) not null default 0,
  professional_tax numeric(12,2) not null default 0,
  other_deductions numeric(12,2) not null default 0,
  net_pay numeric(12,2) not null,
  breakdown jsonb not null default '{}'::jsonb, -- full snapshot for the payslip printout
  created_at timestamptz default now(),
  unique (payroll_run_id, employee_id)
);

-- ---------- 6. SETTINGS (key-value store for statutory config) ----------
create table if not exists settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz default now()
);

insert into settings (key, value) values
  ('pf', '{"employee_rate": 12, "employer_rate": 12, "wage_ceiling": 15000}'),
  ('esi', '{"employee_rate": 0.75, "employer_rate": 3.25, "wage_ceiling": 21000}'),
  ('pt_slabs_ap', '[
      {"min": 0, "max": 15000, "amount": 0},
      {"min": 15001, "max": 20000, "amount": 150},
      {"min": 20001, "max": null, "amount": 200}
   ]'),
  ('pt_march_extra', '{"enabled": true, "amount": 300}'),
  ('school_name', '"Friends Vidyanikethan School"')
on conflict (key) do nothing;

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================
alter table profiles enable row level security;
alter table employees enable row level security;
alter table attendance enable row level security;
alter table payroll_runs enable row level security;
alter table payslips enable row level security;
alter table settings enable row level security;

-- Helper: get current user's role
create or replace function current_role_name()
returns text as $$
  select role from profiles where id = auth.uid();
$$ language sql stable security definer;

-- Profiles: users can read all profiles (needed for name lookups), only admin edits roles
create policy "profiles_select_all" on profiles for select using (auth.uid() is not null);
create policy "profiles_update_own_or_admin" on profiles for update
  using (auth.uid() = id or current_role_name() = 'admin');

-- Employees: viewer=read, accountant/admin=write
create policy "employees_select" on employees for select using (auth.uid() is not null);
create policy "employees_write" on employees for insert with check (current_role_name() in ('admin','accountant'));
create policy "employees_update" on employees for update using (current_role_name() in ('admin','accountant'));
create policy "employees_delete" on employees for delete using (current_role_name() = 'admin');

-- Attendance: viewer=read, accountant/admin=write
create policy "attendance_select" on attendance for select using (auth.uid() is not null);
create policy "attendance_insert" on attendance for insert with check (current_role_name() in ('admin','accountant'));
create policy "attendance_update" on attendance for update using (current_role_name() in ('admin','accountant'));
create policy "attendance_delete" on attendance for delete using (current_role_name() in ('admin','accountant'));

-- Payroll runs: viewer=read, accountant/admin=write; only admin finalizes/deletes
create policy "runs_select" on payroll_runs for select using (auth.uid() is not null);
create policy "runs_insert" on payroll_runs for insert with check (current_role_name() in ('admin','accountant'));
create policy "runs_update" on payroll_runs for update using (current_role_name() in ('admin','accountant'));
create policy "runs_delete" on payroll_runs for delete using (current_role_name() = 'admin');

-- Payslips: viewer=read, accountant/admin=write
create policy "payslips_select" on payslips for select using (auth.uid() is not null);
create policy "payslips_insert" on payslips for insert with check (current_role_name() in ('admin','accountant'));
create policy "payslips_update" on payslips for update using (current_role_name() in ('admin','accountant'));
create policy "payslips_delete" on payslips for delete using (current_role_name() in ('admin','accountant'));

-- Settings: everyone reads, only admin writes
create policy "settings_select" on settings for select using (auth.uid() is not null);
create policy "settings_update" on settings for update using (current_role_name() = 'admin');
create policy "settings_insert" on settings for insert with check (current_role_name() = 'admin');
