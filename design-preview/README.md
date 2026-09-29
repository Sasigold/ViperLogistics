# תצוגת עיצוב (לא לפרודקשן)

עיצוב בלבד — אין נגיעה ב-`src`. הכל CSS שמוזרק בדפדפן מעל האפליקציה, עם נתוני דמה (`fixtures.mjs`) במקום Supabase.

    npm i --no-save playwright-core
    VITE_SUPABASE_URL=https://demo.supabase.co VITE_SUPABASE_ANON_KEY=demo npx vite --port 5199 &
    node design-preview/shoot.mjs baseline   # המצב הנוכחי
    node design-preview/shoot.mjs soft       # וריאנט A
    node design-preview/shoot.mjs pro        # וריאנט B

צילומים ב-`shots/<variant>/`. וריאנטים ב-`variants/*.css`.
