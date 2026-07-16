-- ============================================================================
-- Friends School Payroll — Migration: Employee Self-Service Portal
-- Run this AFTER schema.sql, in Supabase SQL Editor.
-- Adds: employee logins linked to employee records, morning/afternoon
-- geo-tagged attendance marking, automatic Casual-Leave / Loss-of-Pay logic,
-- and locks down RLS so employee logins can only ever see their own data.
-- ============================================================================

-- ---------- 1. Link employees to an auth user (nullable — set on signup) ----------
alter table employees add column if not exists user_id uuid unique references auth.users(id);

-- ---------- 2. Allow the new 'employee' role ----------
alter table profiles drop constraint if exists profiles_role_check;
alter table profiles add constraint profiles_role_check check (role in ('admin','accountant','viewer','employee'));

-- ---------- 3. Daily, twice-a-day, geo-tagged attendance ----------
create table if not exists daily_attendance (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  date date not null,
  morning_marked_at timestamptz,
  morning_lat numeric(9,6),
  morning_lng numeric(9,6),
  afternoon_marked_at timestamptz,
  afternoon_lat numeric(9,6),
  afternoon_lng numeric(9,6),
  created_at timestamptz default now(),
  unique (employee_id, date)
);
alter table daily_attendance enable row level security;

-- ---------- 4. Settings: CL policy + school location for geo-fencing ----------
insert into settings (key, value) values
  ('leave_policy', '{"cl_per_month": 2}'),
  ('school_location', '{"enabled": false, "lat": null, "lng": null, "radius_m": 200}')
on conflict (key) do nothing;

-- ---------- 5. Helper: employee_id for the currently logged-in user ----------
create or replace function current_employee_id()
returns uuid as $$
  select id from employees where user_id = auth.uid();
$$ language sql stable security definer;

-- ---------- 6. Self-signup linking (security definer — bypasses RLS safely) ----------
create or replace function link_employee_account(p_emp_code text)
returns json as $$
declare
  v_emp employees;
begin
  select * into v_emp from employees where emp_code = p_emp_code and user_id is null;
  if not found then
    return json_build_object('success', false, 'message', 'No unlinked employee found with that code. Contact the school office.');
  end if;
  update employees set user_id = auth.uid() where id = v_emp.id;
  update profiles set role = 'employee' where id = auth.uid();
  return json_build_object('success', true, 'employee_id', v_emp.id, 'full_name', v_emp.full_name);
end;
$$ language plpgsql security definer;

-- ============================================================================
-- RLS — tighten existing tables now that employee logins exist.
-- Employee logins must NEVER see other staff's salary/bank/PAN data.
-- ============================================================================

-- Employees: staff (admin/accountant/viewer) see everyone; an employee login sees only their own row
drop policy if exists "employees_select" on employees;
create policy "employees_select" on employees for select using (
  current_role_name() in ('admin','accountant','viewer')
  or id = current_employee_id()
);

-- Payslips: staff see everyone; an employee login sees only their own FINALIZED payslips
drop policy if exists "payslips_select" on payslips;
create policy "payslips_select" on payslips for select using (
  current_role_name() in ('admin','accountant','viewer')
  or (employee_id = current_employee_id()
      and payroll_run_id in (select id from payroll_runs where status = 'finalized'))
);

-- Monthly attendance (admin-entered grid): staff only — employee logins use daily_attendance instead
drop policy if exists "attendance_select" on attendance;
create policy "attendance_select" on attendance for select using (
  current_role_name() in ('admin','accountant','viewer')
);

-- ---------- Daily attendance policies ----------
create policy "daily_att_select" on daily_attendance for select using (
  current_role_name() in ('admin','accountant','viewer') or employee_id = current_employee_id()
);
create policy "daily_att_insert" on daily_attendance for insert with check (
  employee_id = current_employee_id() or current_role_name() in ('admin','accountant')
);
create policy "daily_att_update" on daily_attendance for update using (
  employee_id = current_employee_id() or current_role_name() in ('admin','accountant')
);
