# תצוגת עיצוב (לא לפרודקשן)

עיצוב בלבד — אין נגיעה ב-`src`. הכל CSS שמוזרק בדפדפן מעל האפליקציה, עם נתוני דמה (`fixtures.mjs`) במקום Supabase.

    npm i --no-save playwright-core
    VITE_SUPABASE_URL=https://demo.supabase.co VITE_SUPABASE_ANON_KEY=demo npx vite --port 5199 &
    node design-preview/shoot.mjs baseline   # המצב הנוכחי
    node design-preview/shoot.mjs soft       # וריאנט A
    node design-preview/shoot.mjs pro        # וריאנט B
    node design-preview/shoot.mjs nova       # וריאנט C (NOVA) — הנבחר
    MOBILE=1 node design-preview/shoot.mjs nova   # מובייל

צילומים ב-`shots/<variant>/`. וריאנטים ב-`variants/*.css`.

## Layout Lab — מבנה שונה, לא רק עיצוב

מסכים חלופיים במבנה חדש (בלי לגעת ב-`src`), עם אותם נתונים ואותן טבלאות:

    http://localhost:5199/design-preview/lab/index.html?page=calendar|dispatch|event&theme=light|dark
    node design-preview/shoot-lab.mjs        # צילומי מסך (MOBILE=1 למובייל)

* `CalendarLab` — אג'נדה לפי יום + חלונית פרטים (master–detail) + כרטיסי סיכום
* `DispatchLab` — ציר זמן עם נתיב לכל משאית + רשימת משימות + "דורש תשומת לב"
* `EventLab` — "סיפור האירוע": מוכנות, מהלך היום, כרטיסי משימה, מפה, כסף, יומן
