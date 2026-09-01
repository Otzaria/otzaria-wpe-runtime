/*
 * Copyright (C) 2026 Otzaria project. Same license as WebKit (LGPL-2.1/BSD).
 *
 * See WebPrintOperationWPE.h. The Skia page-recording flow mirrors
 * WebPrintOperationGtk (gtk/WebPrintOperationGtk.cpp) minus the GTK print
 * settings: no page ranges, copies, n-up or rotation.
 */

#include "config.h"
#include "WebPrintOperationWPE.h"

#if PLATFORM(WPE)

#include <WebCore/Document.h>
#include <WebCore/FrameDestructionObserverInlines.h>
#include <WebCore/LocalFrame.h>
#include <WebCore/PrintContext.h>
#include <WebCore/ResourceError.h>
#include <wtf/TZoneMallocInlines.h>
#include <wtf/glib/GRefPtr.h>
#include <wtf/glib/GUniquePtr.h>

#if USE(SKIA)
#include <WebCore/GraphicsContextSkia.h>
WTF_IGNORE_WARNINGS_IN_THIRD_PARTY_CODE_BEGIN
#include <skia/core/SkCanvas.h>
#include <skia/core/SkPicture.h>
#include <skia/core/SkPictureRecorder.h>
#include <skia/core/SkStream.h>
#include <skia/docs/SkPDFDocument.h>
WTF_IGNORE_WARNINGS_IN_THIRD_PARTY_CODE_END
#endif

namespace WebKit {

WTF_MAKE_TZONE_ALLOCATED_IMPL(WebPrintOperationWPE);

WebPrintOperationWPE::WebPrintOperationWPE(const PrintInfo& printInfo)
    : m_printInfo(printInfo)
{
}

WebPrintOperationWPE::~WebPrintOperationWPE() = default;

#if USE(SKIA)
static SkPDF::DateTime skiaDateTimeNow()
{
    GRefPtr<GDateTime> now = adoptGRef(g_date_time_new_now_local());
    return SkPDF::DateTime {
        .fTimeZoneMinutes = static_cast<int16_t>((g_date_time_get_utc_offset(now.get()) / G_USEC_PER_SEC) * 60),
        .fYear = static_cast<uint16_t>(g_date_time_get_year(now.get())),
        .fMonth = static_cast<uint8_t>(g_date_time_get_month(now.get())),
        .fDayOfWeek = static_cast<uint8_t>(g_date_time_get_day_of_week(now.get()) % 7),
        .fDay = static_cast<uint8_t>(g_date_time_get_day_of_month(now.get())),
        .fHour = static_cast<uint8_t>(g_date_time_get_hour(now.get())),
        .fMinute = static_cast<uint8_t>(g_date_time_get_minute(now.get())),
        .fSecond = static_cast<uint8_t>(g_date_time_get_second(now.get()))
    };
}
#endif

void WebPrintOperationWPE::startPrint(WebCore::PrintContext* printContext, CompletionHandler<void(RefPtr<WebCore::FragmentedSharedBuffer>&&, WebCore::ResourceError&&)>&& completionHandler)
{
#if USE(SKIA)
    ASSERT(printContext);

    double contentWidth = m_printInfo.availablePaperWidth;
    double contentHeight = m_printInfo.availablePaperHeight;
    double paperWidth = contentWidth + m_printInfo.margin.left() + m_printInfo.margin.right();
    double paperHeight = contentHeight + m_printInfo.margin.top() + m_printInfo.margin.bottom();

    SkDynamicMemoryWStream memoryBuffer;
    SkPDF::Metadata metadata;
    metadata.fCreation = skiaDateTimeNow();
    metadata.fModified = metadata.fCreation;
    if (auto* document = printContext->frame()->document()) {
        auto title = document->title().utf8();
        metadata.fTitle = SkString(title.data(), title.length());
    }

    auto document = SkPDF::MakeDocument(&memoryBuffer, metadata);
    ASSERT(document);
    int pageCount = printContext->pageCount();
    for (int i = 0; i < pageCount; ++i) {
        SkPictureRecorder recorder;
        auto* canvas = recorder.beginRecording(paperWidth, paperHeight);
        canvas->save();
        canvas->translate(m_printInfo.margin.left(), m_printInfo.margin.top());
        WebCore::GraphicsContextSkia graphicsContext(*canvas, WebCore::RenderingMode::Unaccelerated, WebCore::RenderingPurpose::Unspecified);
        printContext->spoolPage(graphicsContext, i, contentWidth);
        canvas->restore();
        auto picture = recorder.finishRecordingAsPicture();
        auto* pageCanvas = document->beginPage(paperWidth, paperHeight);
        pageCanvas->drawPicture(picture);
        document->endPage();
    }
    document->close();

    completionHandler(WebCore::FragmentedSharedBuffer::create(memoryBuffer.detachAsData()), { });
#else
    UNUSED_PARAM(printContext);
    completionHandler(nullptr, WebCore::ResourceError("WebKitErrorDomain"_s, 0, { }, "Print to PDF requires the Skia backend"_s));
#endif
}

} // namespace WebKit

#endif // PLATFORM(WPE)
