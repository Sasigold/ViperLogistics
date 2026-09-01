-- 0148: עובד שמשויך לקבלן נכנס לסגל שלו, ועובד קבלן נכנס לדף האירוע
--
-- שתי דלתות שהבקשה 0148 פותחת, שתיהן בצד של הקבלן:
--
-- 1. **עובד שהמשרד משייך לקבלן במסך העובדים מופיע אצל הקבלן.** מאגר השיבוץ
--    (`contractor_assignable_workers`) איחד עד כה את הרוסטר עם חשבונות
--    `contractor_user` בלבד — עובד *צוות* שנושא `contractor_id` (הכובע הכפול
--    של 0075) מעולם לא הופיע ברשימת העובדים של הקבלן שלו, ולא בבורר השיבוץ.
--    ההגבלה יורדת: כל פרופיל חי שמשויך לקבלן הוא חלק מהסגל שלו. זה אותו
--    היגיון של 0103 ("מנהל הקבלן הוא גם עובד") צעד אחד הלאה — מי שמשויך
--    לקבלן ניתן לשיבוץ אצלו, ויהא סוג החשבון אשר יהא. `contractor_assign_worker`
--    כבר יודע לגשר חשבון בלי שורת סגל (0121), ולא נדרש בו שינוי.
--
-- 2. **עובד קבלן לוחץ על משימה בלו״ז ומגיע לאירוע.** ‏RLS כבר פותחת לו את
--    שורת האירוע (`on_event_as_contractor_worker`, ‏0066 — רק אירוע שיש לו
--    בו משימה *משובצת*), אבל דלת המסך — `events.view` שהראוטר שואל על
--    ‏`/events/:id` — מעולם לא נפתחה לתפקידו. התוצאה הייתה לחיצה שאינה עושה
--    דבר: כרטיס המשימה סגור לו (הוא של מנהל המערכת, 0108), והנפילה לדף
--    האירוע נעצרה על המפתח. אותו מהלך בדיוק של 0103 על מנהל הקבלן, לתפקיד
--    העובד: המפתח פותח את הדלת, ו-RLS ממשיכה להכריע אילו שורות יש מאחוריה.

-- ===== 1. כל פרופיל משויך הוא חלק מהמאגר ==================================
-- הגוף זהה ל-0121 מלבד זרוע האיחוד השנייה: `user_kind` כבר אינו מסנן.
-- ‏customer_user אינו נושא `contractor_id` בכלל (מסך העובדים מאפס אותו),
-- ולכן התנאי על הקבלן לבדו כבר תוחם את הרשימה.
create or replace function contractor_assignable_workers(p_contractor_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_ctr uuid := app.contractor_id();
begin
  if v_ctr is null then
    v_ctr := p_contractor_id;
    if v_ctr is not null and not app.is_admin() then
      perform app.require('contractors.manage_workers');
    end if;
  end if;
  if v_ctr is null then return '[]'::jsonb; end if;

  return coalesce((
    select jsonb_agg(x order by x->>'full_name')
    from (
      select jsonb_build_object(
               'worker_id',  w.id,
               'profile_id', p.id,
               'full_name',  w.full_name,
               'phone',      w.phone,
               'has_login',  p.id is not null,
               'roles',      coalesce((select jsonb_agg(r.role order by r.role)
                                         from contractor_worker_roles r
                                        where r.contractor_worker_id = w.id), '[]'::jsonb)) as x,
             w.full_name
        from contractor_workers w
        left join profiles p
               on p.contractor_worker_id = w.id and p.deleted_at is null
       where w.contractor_id = v_ctr and w.deleted_at is null and w.is_active

      union all

      -- חשבונות תחת אותו קבלן שאין להם שורת רוסטר — עובד קבלן שהמשרד יצר,
      -- או איש צוות שהמשרד שייך לקבלן (0075/0148). אין להם שורת עובד ⇒ אין
      -- להם תפקידים להגדיר עדיין; `contractor_assign_worker` יגשר בשיבוץ.
      select jsonb_build_object(
               'worker_id',  null,
               'profile_id', p.id,
               'full_name',  p.full_name,
               'phone',      p.phone,
               'has_login',  true,
               'roles',      '[]'::jsonb),
             p.full_name
        from profiles p
       where p.contractor_id = v_ctr
         and p.contractor_worker_id is null
         and p.deleted_at is null and p.is_active
    ) t(x, full_name)
  ), '[]'::jsonb);
end $$;

revoke execute on function public.contractor_assignable_workers(uuid) from anon, public;

-- ===== 2. הדלת של דף האירוע נפתחת גם לעובד הקבלן ==========================
-- ‏`events.list` נשאר סגור — רשימת כל האירועים אינה שלו. מה שנפתח הוא הדף
-- של אירוע שממילא מותר לו לקרוא: משימה משובצת שהוא מופיע בה.
insert into role_permissions (role_id, permission_key, allowed)
select r.id, 'events.view', true
from permission_roles r
where r.key = 'contractor_worker'
on conflict (role_id, permission_key) do update set allowed = true;
