// SPDX-License-Identifier: GPL-3.0-only

#include "ThumbnailImageProvider.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QImageReader>
#include <QQuickTextureFactory>
#include <QRunnable>
#include <QStandardPaths>
#include <QThreadPool>
#include <QUrl>

namespace {

class ThumbnailResponse final : public QQuickImageResponse, public QRunnable {
  public:
    ThumbnailResponse(const QString& path, const QSize& requested)
        : m_path(path), m_requested(requested) {
        setAutoDelete(false);
    }

    QQuickTextureFactory* textureFactory() const override {
        return QQuickTextureFactory::textureFactoryForImage(m_image);
    }

    QString errorString() const override {
        return m_error;
    }

    void run() override {
        const int w = m_requested.width() > 0 ? m_requested.width() : 256;
        const int h = m_requested.height() > 0 ? m_requested.height() : 256;

        const QFileInfo info(m_path);
        if (!info.exists() || !info.isFile()) {
            m_error = QStringLiteral("File not found: %1").arg(m_path);
            emit finished();
            return;
        }

        const QString cacheDir =
            QStandardPaths::writableLocation(QStandardPaths::CacheLocation) +
            QStringLiteral("/thumbnails");
        QDir().mkpath(cacheDir);
        const QString key = QStringLiteral("%1|%2|%3|%4x%5")
                                .arg(m_path)
                                .arg(info.size())
                                .arg(info.lastModified().toMSecsSinceEpoch())
                                .arg(w)
                                .arg(h);
        const QString cacheFile =
            cacheDir + QLatin1Char('/') +
            QString::fromLatin1(
                QCryptographicHash::hash(key.toUtf8(), QCryptographicHash::Sha1).toHex()) +
            QStringLiteral(".png");

        QImage cached;
        if (QFileInfo::exists(cacheFile) && cached.load(cacheFile)) {
            m_image = cached;
            emit finished();
            return;
        }

        QImageReader reader(m_path);
        reader.setAutoTransform(true);
        const QSize original = reader.size();
        if (original.isValid() && !original.isEmpty()) {
            reader.setScaledSize(original.scaled(w, h, Qt::KeepAspectRatio));
        }
        QImage image = reader.read();
        if (image.isNull()) {
            m_error = reader.errorString();
            emit finished();
            return;
        }

        m_image = image;
        // Best-effort cache write; ignore failures.
        image.save(cacheFile, "PNG");
        emit finished();
    }

  private:
    QString m_path;
    QSize m_requested;
    QImage m_image;
    QString m_error;
};

} // namespace

QQuickImageResponse* ThumbnailImageProvider::requestImageResponse(const QString& id,
                                                                  const QSize& requestedSize) {
    QString path = id;
    const int query = path.indexOf(QLatin1Char('?'));
    if (query >= 0) {
        path = path.left(query);
    }
    path = QUrl::fromPercentEncoding(path.toUtf8());

    auto* response = new ThumbnailResponse(path, requestedSize);
    QThreadPool::globalInstance()->start(response);
    return response;
}
