/*
 * Copyright (C) 2026 Otzaria project. Same license as WebKit (LGPL-2.1/BSD).
 *
 * Print-to-PDF for the WPE port. WPE has no printing stack (the WebKit print
 * API lives in the GTK port only), so this renders every page of a
 * PrintContext straight into a PDF with fixed settings: all pages, a single
 * copy, page geometry taken from PrintInfo. Serves the DrawPagesForPrinting
 * message, which the Otzaria WPE build enables for PLATFORM(WPE).
 */

#pragma once

#if PLATFORM(WPE)

#include "PrintInfo.h"
#include <WebCore/SharedBuffer.h>
#include <wtf/CompletionHandler.h>
#include <wtf/TZoneMalloc.h>

namespace WebCore {
class PrintContext;
class ResourceError;
}

namespace WebKit {

class WebPrintOperationWPE {
    WTF_MAKE_TZONE_ALLOCATED(WebPrintOperationWPE);
public:
    explicit WebPrintOperationWPE(const PrintInfo&);
    ~WebPrintOperationWPE();

    void startPrint(WebCore::PrintContext*, CompletionHandler<void(RefPtr<WebCore::FragmentedSharedBuffer>&&, WebCore::ResourceError&&)>&&);

private:
    PrintInfo m_printInfo;
};

} // namespace WebKit

#endif // PLATFORM(WPE)
