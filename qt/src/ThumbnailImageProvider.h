// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include <QQuickAsyncImageProvider>

// Asynchronous image provider for "image://thumb/<percent-encoded-abs-path>".
// Decodes and downscales images off the GUI thread (QImageReader on a thread
// pool) and caches the rendered thumbnail on disk keyed by path+size+mtime so
// scrolling a large result set stays responsive.
class ThumbnailImageProvider final : public QQuickAsyncImageProvider {
  public:
    QQuickImageResponse* requestImageResponse(const QString& id,
                                              const QSize& requestedSize) override;
};
