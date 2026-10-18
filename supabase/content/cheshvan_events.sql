-- ============================================================
-- מפגשי חשוון תשפ״ז
-- ============================================================

insert into events (month_id, kind, event_date, title, is_mandatory)
select m.id, e.kind::event_kind, e.d::date, e.title, e.req
from months m,
     (values
       ('class',   '2026-10-27', 'השיעור השבועי',          true),
       ('shabbat', '2026-10-30', 'שבת קבוצתית — מתחילות בערב שבת י״ט חשוון', true),
       ('class',   '2026-11-03', 'השיעור השבועי',          true),
       ('class',   '2026-11-10', 'השיעור השבועי',          true)
     ) as e(kind, d, title, req)
where m.hebrew_name = 'חשוון';
