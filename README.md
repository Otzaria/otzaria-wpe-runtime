# otzaria-wpe-runtime

בנייה חד-פעמית של **WPE WebKit** מהמקור ב-GitHub Actions, ופרסום *tarball* של
SDK + runtime. ה-CI של אפליקציית Otzaria צורך את ה-tarball הזה כדי לבנות ולארוז
הפצת לינוקס *self-contained* עם `flutter_inappwebview_linux`, בלי לבנות את WebKit
בכל build של האפליקציה (בנייה מהמקור ~שעות).

## למה בונים בעצמנו (ולמה DEVELOPER_MODE)

- `flutter_inappwebview_linux` דורש **WPE ≥ 2.40** ומשתמש ב-WPE Platform API
  (`wpe-platform-2.0` + הבקאנד ה-headless).
- בהפצה מחוץ ל-prefix המערכתי, תהליכי העזר של WebKit
  (`WPEWebProcess` / `WPENetworkProcess`) מופנים בזמן ריצה דרך
  משתנה הסביבה **`WEBKIT_EXEC_PATH`**.
- אימתנו מול מקור WebKit ש-`WEBKIT_EXEC_PATH` נכבד **רק** כאשר WebKit נבנה עם
  `ENABLE(DEVELOPER_MODE)`. לכן הבנייה כאן היא עם `-DDEVELOPER_MODE=ON`.
  (מדובר בדגל build של הפורט, לא ב"מצב דיבאג" — הבנייה עצמה Release.)
- ה-sandbox של bubblewrap עוקף הפניות נתיבים ובעייתי מחוץ ל-prefix המערכתי,
  ולכן `-DENABLE_BUBBLEWRAP_SANDBOX=OFF`.

## מה נבנה

| רכיב | גרסה | sha256 (tarball) |
|------|------|------------------|
| WPE WebKit | 2.48.7 | `cecf4984…b690` |
| libwpe | 1.16.3 | `c880fa8d…1420` |

הגרסאות הן ברירת המחדל; ניתן לעקוף אותן ב-`workflow_dispatch`.
ה-`sha256` המלא + סביבת הבנייה נכתבים לקובץ `VERSIONS` בתוך ה-tarball.

> הערה: נכון להיום זו הגרסה היציבה האחרונה בסדרת **2.48** (לפי דרישת המשימה).
> קיימות סדרות יציבות חדשות יותר (2.50.x, 2.52.x) — אפשר לבנות אותן פשוט
> ע"י מסירת גרסה + sha256 אחרים ל-`workflow_dispatch`, ללא שינוי קוד.

## דגלי הבנייה המרכזיים

```
-DPORT=WPE  -DCMAKE_BUILD_TYPE=Release  -DCMAKE_INSTALL_PREFIX=/opt/wpe-sdk
-DDEVELOPER_MODE=ON                 # ⇐ הכרחי ל-WEBKIT_EXEC_PATH
-DENABLE_WPE_PLATFORM=ON
-DENABLE_WPE_PLATFORM_HEADLESS=ON
-DENABLE_WPE_PLATFORM_WAYLAND=OFF   # לא נדרש להטמעה headless
-DENABLE_WPE_PLATFORM_DRM=OFF       # חוסך את תלות ה-GBM
-DENABLE_BUBBLEWRAP_SANDBOX=OFF     # ⇐ הכרחי להפצה ניידת
# כיבוי מה ש-DEVELOPER_MODE הדליק אך לא נדרש (חוסך זמן/תלויות):
-DENABLE_MINIBROWSER=OFF -DENABLE_COG=OFF -DENABLE_API_TESTS=OFF
-DENABLE_LAYOUT_TESTS=OFF -DENABLE_WPE_QT_API=OFF -DENABLE_THUNDER=OFF
-DENABLE_JSC_RESTRICTED_OPTIONS_BY_DEFAULT=OFF
-DENABLE_DOCUMENTATION=OFF -DENABLE_INTROSPECTION=OFF
-DENABLE_GAMEPAD=OFF -DENABLE_WEBDRIVER=OFF -DENABLE_SPEECH_SYNTHESIS=OFF
```

יכולות ה-web הסטנדרטיות נשארות דלוקות כברירת מחדל (JS מלא, fetch, WebSocket,
IndexedDB, canvas, OffscreenCanvas, WebGL דרך תהליך ה-GPU, WebAssembly,
Service Workers). **מדיה (GStreamer)** נשארת דלוקה כברירת המחדל של WPE — זהו
מרכיב זמן הבנייה המשמעותי ביותר, וניתן לכבותו בעתיד אם יידרש קיצוץ.

שימו לב: פלאגיני GStreamer נטענים ב-`dlopen` ולכן **אינם נארזים** בסגירת
ה-`ldd` של הצרכן — וידאו/אודיו ב-WebView יעבדו רק אם GStreamer מותקן במארח.
ליבת הגלישה אינה תלויה בכך.

## מבנה הריפו

```
build.sh                    # כל לוגיקת הבנייה (רץ גם מקומית בקונטיינר)
.github/workflows/build.yml # קונטיינר → תלויות → הורדה+אימות → build → אריזה → release
.gitattributes              # *.sh / *.yml חייבים LF
```

`build.sh` מוריד ומאמת sha256 של שני ה-tarballs מ-`wpewebkit.org`, מתקין את
תלויות הבנייה דרך **הסקריפט הרשמי של WebKit** (`Tools/wpe/install-dependencies`),
בונה קודם `libwpe` (meson) ואז `WPE WebKit` (cmake/ninja), ומתקין ל-`/opt/wpe-sdk`.

## הרצה

- **ידנית:** Actions → `build-wpe-runtime` → `Run workflow` (אפשר לשנות גרסאות).
- **על tag:** דחיפת tag `wpe-*` בונה ומעלה גם כ-GitHub Release.
- **מקומית:**
  ```bash
  docker run --rm -v "$PWD:/w" -w /w debian:bookworm bash build.sh
  ```

## צריכת ה-artifact ב-CI של Otzaria

1. הורידו וחלצו את `wpe-runtime-<ver>-linux-x86_64.tar.zst` (למשל ל-`/opt/wpe-sdk`).
2. לבנייה מול ה-SDK:
   ```bash
   export PKG_CONFIG_PATH=/opt/wpe-sdk/lib/pkgconfig:$PKG_CONFIG_PATH
   export LD_LIBRARY_PATH=/opt/wpe-sdk/lib:$LD_LIBRARY_PATH
   ```
3. באריזה/בזמן ריצה של האפליקציה, הפנו את `WEBKIT_EXEC_PATH` לתיקייה שאליה
   נארזו `WPEWebProcess` / `WPENetworkProcess`. ב-Otzaria זה קורה אוטומטית:
   ה-fork של flutter_inappwebview משטח אותם ל-`lib/` של ה-bundle ומגדיר את
   המשתנה בעצמו בזמן ריצה.

## זמן בנייה וסיכונים

- **אומדן זמן:** בנייה קרה על runner בן 4 ליבות (WebCore + JSC + Skia) ריאלית
  ~3–5 שעות. לכן `NINJA_TIMEOUT=320m` עוצר את `ninja` בחן לפני מגבלת 6 השעות
  של ה-job, וה-ccache נשמר בכל ריצה (מפתח מטמון ייחודי + `restore-keys`).
  **הריצה הראשונה עלולה להיחתך בטיימאאוט — הרצה חוזרת ממשיכה מהמטמון ומסתיימת.**
  בנייה חוזרת (cache חם) — דקות עד עשרות דקות.
- מה שיתברר רק בריצה אמיתית: (א) האם 2.48.7 מתקמפל נקי עם gcc-12 של bookworm;
  (ב) האם צירוף הדגלים (headless ללא wayland/drm, ללא introspection) עובר
  configure/link ללא הפתעה; (ג) האם בנייה קרה נכנסת בפעם הראשונה או דורשת 2 ריצות.
