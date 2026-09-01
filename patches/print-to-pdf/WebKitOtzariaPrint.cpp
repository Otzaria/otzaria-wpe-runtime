/*
 * Copyright (C) 2026 Otzaria project. Same license as WebKit (LGPL-2.1/BSD).
 *
 * Downstream-only WPE API: asynchronously print the current page of a
 * WebKitWebView to an in-memory PDF (real text, laid out by WebCore's print
 * pipeline). Exposed as plain C symbols (webkit_* survives the version
 * script) and consumed via dlsym, so embedders need no patched headers and
 * degrade gracefully on an unpatched libWPEWebKit.
 *
 *   webkit_otzaria_web_view_print_to_pdf(view,
 *       page_width_pt, page_height_pt,
 *       margin_top_pt, margin_right_pt, margin_bottom_pt, margin_left_pt,
 *       cancellable, callback, user_data);
 *   GBytes* webkit_otzaria_web_view_print_to_pdf_finish(view, result, error);
 *
 * All sizes are in PDF points (1/72 inch).
 */

#include "config.h"

#if PLATFORM(WPE)

#include "PrintInfo.h"
#include "WebFrameProxy.h"
#include "WebKitWebViewPrivate.h"
#include "WebPageProxy.h"
#include <WebCore/ResourceError.h>
#include <WebCore/SharedMemory.h>
#include <algorithm>
#include <wtf/glib/GRefPtr.h>

extern "C" {

__attribute__((visibility("default"))) void
webkit_otzaria_web_view_print_to_pdf(WebKitWebView* webView,
    double pageWidthPt, double pageHeightPt,
    double marginTopPt, double marginRightPt, double marginBottomPt, double marginLeftPt,
    GCancellable* cancellable, GAsyncReadyCallback callback, gpointer userData)
{
    g_return_if_fail(WEBKIT_IS_WEB_VIEW(webView));

    GRefPtr<GTask> task = adoptGRef(g_task_new(webView, cancellable, callback, userData));

    auto& page = webkitWebViewGetPage(webView);
    RefPtr frame = page.mainFrame();
    if (!frame) {
        g_task_return_new_error(task.get(), G_IO_ERROR, G_IO_ERROR_FAILED, "Print to PDF failed: no main frame");
        return;
    }

    float contentWidth = static_cast<float>(std::max(1.0, pageWidthPt - marginLeftPt - marginRightPt));
    float contentHeight = static_cast<float>(std::max(1.0, pageHeightPt - marginTopPt - marginBottomPt));
    WebKit::PrintInfo printInfo(1, contentWidth, contentHeight,
        { static_cast<float>(marginTopPt), static_cast<float>(marginRightPt),
          static_cast<float>(marginBottomPt), static_cast<float>(marginLeftPt) });

    page.drawPagesForPrinting(*frame, printInfo,
        [task = WTFMove(task), page = Ref { page }](std::optional<WebCore::SharedMemory::Handle>&& handle, WebCore::ResourceError&& error) mutable {
            page->endPrinting();

            if (!handle || !error.isNull()) {
                g_task_return_new_error(task.get(), G_IO_ERROR, G_IO_ERROR_FAILED,
                    "Print to PDF failed: %s", error.isNull() ? "no data" : error.localizedDescription().utf8().data());
                return;
            }

            auto size = handle->size();
            auto memory = WebCore::SharedMemory::map(WTFMove(*handle), WebCore::SharedMemory::Protection::ReadOnly);
            if (!memory || !size) {
                g_task_return_new_error(task.get(), G_IO_ERROR, G_IO_ERROR_FAILED, "Print to PDF failed: empty result");
                return;
            }

            auto span = memory->span();
            GBytes* bytes = g_bytes_new(span.data(), std::min(size, span.size()));
            g_task_return_pointer(task.get(), bytes, reinterpret_cast<GDestroyNotify>(g_bytes_unref));
        });
}

__attribute__((visibility("default"))) GBytes*
webkit_otzaria_web_view_print_to_pdf_finish(WebKitWebView* webView, GAsyncResult* result, GError** error)
{
    g_return_val_if_fail(WEBKIT_IS_WEB_VIEW(webView), nullptr);
    g_return_val_if_fail(g_task_is_valid(result, webView), nullptr);
    return static_cast<GBytes*>(g_task_propagate_pointer(G_TASK(result), error));
}

} // extern "C"

#endif // PLATFORM(WPE)
