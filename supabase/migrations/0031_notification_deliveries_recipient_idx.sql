-- 0031: אינדקס חסר על מפתח זר שנוסף ב-0030
--
-- notification_deliveries.recipient_id הוא מפתח זר בלי אינדקס — יועץ
-- הביצועים של הפרויקט תפס אותו מיד אחרי ההחלה. מחיקה או עדכון של שורת
-- profiles מחייבים סריקה מלאה כדי לאמת את האילוץ, ושאילתה עתידית לפי
-- נמען (למשל "כל המשלוחים שנכשלו לי") הייתה סורקת את כל הטבלה.

create index if not exists notification_deliveries_recipient_idx
  on notification_deliveries (recipient_id);
