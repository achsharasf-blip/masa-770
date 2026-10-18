-- המשימה החודשית — משימה אחת לכל חודש (יעד ברירת מחדל: 10 פעמים, ניתן לשינוי)
insert into tasks (scope, kind, title, body, start_date, end_date, publish_date, is_required, target_count, sort_order)
select 'month','habit', x.title, x.body, m.start_date, m.end_date, m.start_date, true, x.target, 10
from months m join (values
  ('חשוון','קריאת שמע שעל המיטה או ברכות השחר','אחת מהשתיים, בכל יום שאת מצליחה.',10),
  ('כסלו', 'חלוקת נרות שבת','לצאת לחלק נרות שבת לנשים ולבנות, בחמישי או בשישי.',1),
  ('טבת',  'נטילת ידיים ליד המיטה','להכין כלי וקערה ליד המיטה וליטול ידיים מיד כשקמים.',15),
  ('שבט',  'צדקה לפני הדלקת נרות','לתת צדקה בערב שבת, לפני הדלקת הנרות.',3)
) as x(month_name, title, body, target) on m.hebrew_name = x.month_name;

-- ניגון: האזנה פעם בשבוע (משימה שבועית חוזרת) — נוצר לכל שבוע בנפרד בטעינת התוכן החודשי
