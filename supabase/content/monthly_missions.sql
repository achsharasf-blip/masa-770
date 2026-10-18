-- המשימה החודשית — משימה אחת לכל חודש.
-- בסיס = 50% מהאפשרי; עד 100% = בונוס. חשוון מתחיל בהשקה (21 ימים) ולכן הבסיס 10.
insert into tasks (scope, kind, title, body, start_date, end_date, publish_date, is_required, target_count, max_count, points, extra_points, sort_order)
select 'month','habit', x.title, x.body, m.start_date, m.end_date, m.start_date, true, x.base, x.maxc, 20, x.extra, 10
from months m join (values
  ('חשוון','קריאת שמע שעל המיטה או ברכות השחר','אחת מהשתיים, בכל יום שאת מצליחה.',10,21,1),
  ('כסלו', 'חלוקת נרות שבת','לצאת לחלק נרות שבת לנשים ולבנות, לקראת שבת.',2,4,5),
  ('טבת',  'נטילת ידיים ליד המיטה','להכין כלי וקערה ליד המיטה וליטול ידיים מיד כשקמים.',15,29,1),
  ('שבט',  'צדקה לפני הדלקת נרות','לתת צדקה בערב שבת, לפני הדלקת הנרות.',2,4,5)
) as x(month_name, title, body, base, maxc, extra) on m.hebrew_name = x.month_name;
-- אדר א׳: ממתין להחלטה
