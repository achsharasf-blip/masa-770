-- ============================================================
-- המסע שלי ל־770 — מבנה מסד הנתונים והרשאות (שלב 1)
-- להרצה פעם אחת ב־Supabase → SQL Editor
-- ============================================================

-- ---------- סוגים ----------
create type app_role          as enum ('participant', 'admin');
create type task_scope        as enum ('day', 'week', 'month');
create type task_kind         as enum ('story', 'study', 'video', 'niggun', 'habit', 'mitzvah', 'bonus', 'task');
create type completion_source as enum ('self', 'admin');
create type event_kind        as enum ('class', 'shabbat', 'special', 'other');
create type attendance_status as enum ('present', 'absent', 'excused');

-- ---------- טבלאות ----------

-- רשימת המוזמנות: רק מייל שמופיע כאן יכול להיכנס
create table allowed_emails (
  email        text primary key check (email = lower(email)),
  display_name text not null,
  role         app_role not null default 'participant',
  created_at   timestamptz not null default now()
);

-- פרופיל לכל משתמשת שנכנסה
create table profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  email        text not null unique,
  display_name text not null,
  role         app_role not null default 'participant',
  active       boolean not null default true,
  created_at   timestamptz not null default now()
);

-- חודשי התוכנית
create table months (
  id           serial primary key,
  hebrew_name  text not null,
  hebrew_year  int  not null default 5787,
  start_date   date not null unique,
  end_date     date not null,
  theme        text,
  niggun_title text,
  niggun_url   text,
  niggun_about text,
  check (end_date >= start_date)
);

-- משימות ותכנים (יומי / שבועי / חודשי)
create table tasks (
  id           uuid primary key default gen_random_uuid(),
  scope        task_scope not null,
  kind         task_kind  not null default 'task',
  title        text not null,
  body         text,
  media_url    text,
  start_date   date not null,          -- יומי: היום עצמו | שבועי: יום ראשון | חודשי: תחילת החודש
  end_date     date not null,          -- יומי: אותו יום | שבועי: שבת | חודשי: סוף החודש
  publish_date date not null,          -- ממתי המשתתפות רואות את המשימה
  is_required  boolean not null default true,   -- חובה (תנאי סף) או בונוס
  target_count int  not null default 1 check (target_count >= 1),
                                       -- כמה פעמים בתקופה: נטילת ידיים 15 בחודש, ניגון 1 בשבוע
  sort_order   int  not null default 0,
  created_at   timestamptz not null default now(),
  check (end_date >= start_date)
);
create index tasks_dates_idx on tasks (start_date, end_date);

-- דיווח עצמי של המשתתפות (נפרד לגמרי מניקוד רשמי)
-- שורה לכל ביצוע: משימה יומית — פעם אחת; הרגל חודשי — שורה לכל יום שבוצע
create table completions (
  user_id      uuid not null references profiles(id) on delete cascade,
  task_id      uuid not null references tasks(id)    on delete cascade,
  log_date     date not null,                        -- היום שבו בוצע
  completed_at timestamptz not null default now(),
  is_late      boolean not null default false,       -- סומן בדיעבד
  source       completion_source not null default 'self',
  updated_by   uuid references profiles(id),
  updated_at   timestamptz not null default now(),
  note         text,
  primary key (user_id, task_id, log_date)
);

-- יעד אישי ותובנה לחודש
create table monthly_goals (
  user_id    uuid not null references profiles(id) on delete cascade,
  month_id   int  not null references months(id)   on delete cascade,
  goal_text  text not null check (char_length(goal_text) between 1 and 300),
  reflection text check (char_length(reflection) <= 1000),   -- תובנה / מה לקחתי
  updated_at timestamptz not null default now(),
  primary key (user_id, month_id)
);

-- מפגשים ואירועים: שיעור שבועי, שבת קבוצתית, אירוע מיוחד
create table events (
  id           uuid primary key default gen_random_uuid(),
  month_id     int  not null references months(id) on delete cascade,
  kind         event_kind not null default 'other',
  event_date   date not null,
  title        text not null,
  description  text,
  is_mandatory boolean not null default false
);

-- נוכחות — נרשמת רק על ידי המנהלת; משתתפת רואה רק את שלה
create table attendance (
  user_id     uuid not null references profiles(id) on delete cascade,
  event_id    uuid not null references events(id)   on delete cascade,
  status      attendance_status not null,
  note        text,
  recorded_by uuid not null references profiles(id),
  recorded_at timestamptz not null default now(),
  primary key (user_id, event_id)
);

-- ניקוד רשמי — רק למנהלת, יופעל כשתוגדר שיטת הניקוד
create table official_scores (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles(id) on delete cascade,
  month_id   int  references months(id) on delete set null,
  points     numeric not null,
  note       text,
  given_by   uuid not null references profiles(id),
  created_at timestamptz not null default now()
);

-- ---------- פונקציות עזר ----------

-- התאריך של היום לפי שעון ישראל
create or replace function app_today() returns date
language sql stable as $$
  select (now() at time zone 'Asia/Jerusalem')::date
$$;

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles
                 where id = auth.uid() and role = 'admin' and active)
$$;

create or replace function is_active_user() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and active)
$$;

create or replace function current_month_id() returns int
language sql stable as $$
  select id from months where app_today() between start_date and end_date limit 1
$$;

-- ---------- כניסה סגורה: חסימת מי שלא הוזמנה ----------
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare inv allowed_emails;
begin
  select * into inv from allowed_emails where email = lower(new.email);
  if not found then
    raise exception 'not_invited';
  end if;
  insert into profiles (id, email, display_name, role)
  values (new.id, lower(new.email), inv.display_name, inv.role);
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---------- סימון ביצוע (הדרך היחידה של משתתפת לכתוב דיווח) ----------
-- p_date = היום שבו בוצע. משימה יומית: רק התאריך שלה. הרגל/משימה שבועית/חודשית: כל יום בטווח.
-- מותר: משימות שכבר פורסמו, תאריך עד היום, ורק בתוך החודש הנוכחי.
-- סימון של יום שעבר נרשם אוטומטית כ"בדיעבד".
create or replace function mark_task(p_task_id uuid, p_date date, p_done boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  t       tasks;
  m_start date;
  today   date := app_today();
begin
  if not is_active_user() then raise exception 'not_allowed'; end if;

  select * into t from tasks where id = p_task_id;
  if not found then raise exception 'task_not_found'; end if;

  select start_date into m_start from months where id = current_month_id();
  if m_start is null then raise exception 'no_active_month'; end if;

  if t.publish_date > today then raise exception 'task_not_available_yet'; end if;
  if p_date > today then raise exception 'future_date'; end if;
  if p_date < m_start then raise exception 'outside_current_month'; end if;
  if p_date not between t.start_date and t.end_date then
    raise exception 'date_outside_task';
  end if;

  if p_done then
    insert into completions (user_id, task_id, log_date, is_late, source, updated_by)
    values (auth.uid(), p_task_id, p_date, p_date < today, 'self', auth.uid())
    on conflict (user_id, task_id, log_date) do nothing;
  else
    -- משתתפת יכולה לבטל רק סימון שהיא עצמה עשתה
    delete from completions
    where user_id = auth.uid() and task_id = p_task_id
      and log_date = p_date and source = 'self';
  end if;
end $$;

-- ---------- תיקון דיווח על ידי המנהלת ----------
create or replace function admin_set_completion(
  p_user_id uuid, p_task_id uuid, p_date date, p_done boolean, p_note text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_allowed'; end if;
  if p_done then
    insert into completions (user_id, task_id, log_date, source, updated_by, note)
    values (p_user_id, p_task_id, p_date, 'admin', auth.uid(), p_note)
    on conflict (user_id, task_id, log_date) do update
      set source = 'admin', updated_by = auth.uid(),
          updated_at = now(), note = coalesce(p_note, completions.note);
  else
    delete from completions
    where user_id = p_user_id and task_id = p_task_id and log_date = p_date;
  end if;
end $$;

-- ---------- רישום נוכחות (מנהלת בלבד) ----------
create or replace function admin_set_attendance(
  p_user_id uuid, p_event_id uuid, p_status attendance_status, p_note text default null)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_allowed'; end if;
  insert into attendance (user_id, event_id, status, note, recorded_by)
  values (p_user_id, p_event_id, p_status, p_note, auth.uid())
  on conflict (user_id, event_id) do update
    set status = excluded.status, note = excluded.note,
        recorded_by = auth.uid(), recorded_at = now();
end $$;

revoke all on function mark_task(uuid, date, boolean)                         from public, anon;
revoke all on function admin_set_completion(uuid, uuid, date, boolean, text) from public, anon;
revoke all on function admin_set_attendance(uuid, uuid, attendance_status, text) from public, anon;
grant execute on function mark_task(uuid, date, boolean)                         to authenticated;
grant execute on function admin_set_completion(uuid, uuid, date, boolean, text) to authenticated;
grant execute on function admin_set_attendance(uuid, uuid, attendance_status, text) to authenticated;

-- ---------- הפעלת RLS על כל הטבלאות ----------
alter table allowed_emails  enable row level security;
alter table profiles        enable row level security;
alter table months          enable row level security;
alter table tasks           enable row level security;
alter table completions     enable row level security;
alter table monthly_goals   enable row level security;
alter table events          enable row level security;
alter table attendance      enable row level security;
alter table official_scores enable row level security;

-- ---------- כללי הרשאה ----------
-- מנהלת: גישה מלאה לכל הטבלאות (חוץ מכתיבה ישירה לדיווחים — רק דרך admin_set_completion)
create policy admin_all on allowed_emails  for all to authenticated using (is_admin()) with check (is_admin());
create policy admin_all on profiles        for all to authenticated using (is_admin()) with check (is_admin());
create policy admin_all on months          for all to authenticated using (is_admin()) with check (is_admin());
create policy admin_all on tasks           for all to authenticated using (is_admin()) with check (is_admin());
create policy admin_all on monthly_goals   for all to authenticated using (is_admin()) with check (is_admin());
create policy admin_all on events          for all to authenticated using (is_admin()) with check (is_admin());
create policy admin_all on official_scores for all to authenticated using (is_admin()) with check (is_admin());
create policy admin_read on completions    for select to authenticated using (is_admin());
create policy admin_read on attendance     for select to authenticated using (is_admin());

-- משתתפת: רואה רק את הפרופיל שלה, ואינה יכולה לשנות אותו (כולל תפקיד)
create policy own_profile_read on profiles for select to authenticated
  using (id = auth.uid());

-- חודשים: כל משתמשת פעילה רואה את רשימת החודשים
create policy months_read on months for select to authenticated
  using (is_active_user());

-- משימות: רק אחרי מועד הפרסום
create policy tasks_read on tasks for select to authenticated
  using (is_active_user() and publish_date <= app_today());

-- דיווחים: קריאה של הדיווחים שלה בלבד; כתיבה רק דרך mark_task
create policy own_completions_read on completions for select to authenticated
  using (user_id = auth.uid());

-- יעד אישי: שלה בלבד; עריכה רק לחודש הנוכחי
create policy own_goals_read on monthly_goals for select to authenticated
  using (user_id = auth.uid());
create policy own_goals_insert on monthly_goals for insert to authenticated
  with check (user_id = auth.uid() and is_active_user() and month_id = current_month_id());
create policy own_goals_update on monthly_goals for update to authenticated
  using (user_id = auth.uid() and month_id = current_month_id())
  with check (user_id = auth.uid() and month_id = current_month_id());

-- אירועים: של החודש הנוכחי בלבד
create policy events_read on events for select to authenticated
  using (is_active_user() and month_id = current_month_id());

-- נוכחות: משתתפת רואה רק את הנוכחות שלה, ואינה יכולה לשנות אותה
create policy own_attendance_read on attendance for select to authenticated
  using (user_id = auth.uid());

-- allowed_emails, official_scores: אין גישה למשתתפות בכלל (רק admin_all)
