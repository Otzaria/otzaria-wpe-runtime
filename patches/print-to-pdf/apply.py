# -*- coding: utf-8 -*-
# הפעלת טלאי print-to-PDF ל-WPE על עץ מקור WebKit (מכוון ל-2.48.7):
# פותח את מסלול DrawPagesForPrinting (שקיים רק ב-port של GTK) גם ל-WPE,
# מוסיף אופרטור הדפסה רזה מבוסס Skia-PDF, וחושף API בסימבולי C
# (webkit_otzaria_*) שנצרך ב-dlsym מ-flutter_inappwebview_linux.
#
# שימוש: python3 apply.py <webkit-source-dir>
import shutil
import sys
from pathlib import Path

SRC = Path(sys.argv[1])
HERE = Path(__file__).resolve().parent
WK = SRC / "Source" / "WebKit"


def edit(relpath, old, new):
    path = WK / relpath
    text = path.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"print-to-pdf patch: anchor not unique ({count}x) in {relpath}:\n{old}")
    path.write_text(text.replace(old, new))
    print(f"  patched {relpath}")


# קבצים חדשים
dest_op = WK / "WebProcess" / "WebPage" / "wpe"
shutil.copy(HERE / "WebPrintOperationWPE.h", dest_op)
shutil.copy(HERE / "WebPrintOperationWPE.cpp", dest_op)
shutil.copy(HERE / "WebKitOtzariaPrint.cpp", WK / "UIProcess" / "API" / "wpe")
print("  copied WebPrintOperationWPE.{h,cpp}, WebKitOtzariaPrint.cpp")

# WebPage.h: include, הכרזת המתודה, וחבר האופרטור
edit("WebProcess/WebPage/WebPage.h",
     '#if PLATFORM(GTK)\n#include "ArgumentCodersGtk.h"\n#include "WebPrintOperationGtk.h"\n#endif\n',
     '#if PLATFORM(GTK)\n#include "ArgumentCodersGtk.h"\n#include "WebPrintOperationGtk.h"\n#endif\n'
     '\n#if PLATFORM(WPE)\n#include "WebPrintOperationWPE.h"\n#endif\n')

edit("WebProcess/WebPage/WebPage.h",
     '#if PLATFORM(GTK)\n    void drawPagesForPrinting(WebCore::FrameIdentifier',
     '#if PLATFORM(GTK) || PLATFORM(WPE)\n    void drawPagesForPrinting(WebCore::FrameIdentifier')

edit("WebProcess/WebPage/WebPage.h",
     '#if PLATFORM(GTK)\n    std::unique_ptr<WebPrintOperationGtk> m_printOperation;\n#endif',
     '#if PLATFORM(GTK)\n    std::unique_ptr<WebPrintOperationGtk> m_printOperation;\n'
     '#elif PLATFORM(WPE)\n    std::unique_ptr<WebPrintOperationWPE> m_printOperation;\n#endif')

# WebPage.cpp: יצירת האופרטור ופתיחת המימוש
edit("WebProcess/WebPage/WebPage.cpp",
     '#if PLATFORM(GTK)\n    if (!m_printOperation)\n        m_printOperation = makeUnique<WebPrintOperationGtk>(printInfo);\n#endif',
     '#if PLATFORM(GTK)\n    if (!m_printOperation)\n        m_printOperation = makeUnique<WebPrintOperationGtk>(printInfo);\n'
     '#elif PLATFORM(WPE)\n    if (!m_printOperation)\n        m_printOperation = makeUnique<WebPrintOperationWPE>(printInfo);\n#endif')

edit("WebProcess/WebPage/WebPage.cpp",
     '#elif PLATFORM(GTK)\nvoid WebPage::drawPagesForPrinting(',
     '#elif PLATFORM(GTK) || PLATFORM(WPE)\nvoid WebPage::drawPagesForPrinting(')

# הודעת ה-IPC
edit("WebProcess/WebPage/WebPage.messages.in",
     '#if PLATFORM(GTK)\n    DrawPagesForPrinting(',
     '#if PLATFORM(GTK) || PLATFORM(WPE)\n    DrawPagesForPrinting(')

# צד ה-UIProcess
edit("UIProcess/WebPageProxy.h",
     '#elif PLATFORM(GTK)\n    void drawPagesForPrinting(WebFrameProxy&',
     '#elif PLATFORM(GTK) || PLATFORM(WPE)\n    void drawPagesForPrinting(WebFrameProxy&')

edit("UIProcess/WebPageProxy.cpp",
     '#elif PLATFORM(GTK)\nvoid WebPageProxy::drawPagesForPrinting(',
     '#elif PLATFORM(GTK) || PLATFORM(WPE)\nvoid WebPageProxy::drawPagesForPrinting(')

# רישום הקבצים החדשים בבנייה
edit("SourcesWPE.txt",
     'UIProcess/API/wpe/WebKitInputMethodContextImplWPE.cpp @no-unify\n',
     'UIProcess/API/wpe/WebKitInputMethodContextImplWPE.cpp @no-unify\n'
     'UIProcess/API/wpe/WebKitOtzariaPrint.cpp @no-unify\n')

edit("SourcesWPE.txt",
     'WebProcess/WebPage/wpe/WebPageWPE.cpp\n',
     'WebProcess/WebPage/wpe/WebPageWPE.cpp\n'
     'WebProcess/WebPage/wpe/WebPrintOperationWPE.cpp\n')

print("print-to-pdf patch applied")
