#include "cutils.hpp"

#include <QtGui/qicon.h>
#include <QtConcurrent/qtconcurrentrun.h>
#include <QtQuick/qquickitemgrabresult.h>
#include <QtQuick/qquickwindow.h>
#include <QtCore/qcoreapplication.h>
#include <QtCore/qlocale.h>
#include <QtCore/qtranslator.h>
#include <qdir.h>
#include <qfileinfo.h>
#include <qfuturewatcher.h>
#include <qloggingcategory.h>
#include <qqmlengine.h>
#include <qregularexpression.h>

Q_LOGGING_CATEGORY(lcCUtils, "caelestia.cutils", QtInfoMsg)

namespace caelestia {

static QTranslator* s_translator = nullptr;

CUtils::CUtils(QObject* parent) : QObject(parent) {
    if (QIcon::themeName().isEmpty() || QIcon::themeName() == QStringLiteral("hicolor")) {
        QIcon::setThemeName(QStringLiteral("Papirus-Dark"));
        QIcon::setFallbackThemeName(QStringLiteral("hicolor"));
    }
    QMetaObject::invokeMethod(this, [this]() {
        loadTranslation();
    }, Qt::QueuedConnection);
}

void CUtils::saveItem(QQuickItem* target, const QUrl& path) {
    this->saveItem(target, path, QRect(), QJSValue(), QJSValue());
}

void CUtils::saveItem(QQuickItem* target, const QUrl& path, const QRect& rect) {
    this->saveItem(target, path, rect, QJSValue(), QJSValue());
}

void CUtils::saveItem(QQuickItem* target, const QUrl& path, QJSValue onSaved) {
    this->saveItem(target, path, QRect(), onSaved, QJSValue());
}

void CUtils::saveItem(QQuickItem* target, const QUrl& path, QJSValue onSaved, QJSValue onFailed) {
    this->saveItem(target, path, QRect(), onSaved, onFailed);
}

void CUtils::saveItem(QQuickItem* target, const QUrl& path, const QRect& rect, QJSValue onSaved) {
    this->saveItem(target, path, rect, onSaved, QJSValue());
}

void CUtils::saveItem(QQuickItem* target, const QUrl& path, const QRect& rect, QJSValue onSaved, QJSValue onFailed) {
    if (!target) {
        qCWarning(lcCUtils) << "saveItem: a target is required";
        return;
    }

    if (!path.isLocalFile()) {
        qCWarning(lcCUtils) << "saveItem:" << path << "is not a local file";
        return;
    }

    if (!target->window()) {
        qCWarning(lcCUtils) << "saveItem: unable to save target" << target << "without a window";
        return;
    }

    auto scaledRect = rect;
    const qreal scale = target->window()->devicePixelRatio();
    if (rect.isValid() && !qFuzzyCompare(scale + 1.0, 2.0)) {
        scaledRect =
            QRectF(rect.left() * scale, rect.top() * scale, rect.width() * scale, rect.height() * scale).toRect();
    }

    const QSharedPointer<const QQuickItemGrabResult> grabResult = target->grabToImage();

    QObject::connect(grabResult.data(), &QQuickItemGrabResult::ready, this,
        [grabResult, scaledRect, path, onSaved, onFailed, this]() {
            const auto future = QtConcurrent::run([=]() {
                QImage image = grabResult->image();

                if (scaledRect.isValid()) {
                    image = image.copy(scaledRect);
                }

                const QString file = path.toLocalFile();
                const QString parent = QFileInfo(file).absolutePath();
                return QDir().mkpath(parent) && image.save(file);
            });

            auto* watcher = new QFutureWatcher<bool>(this);
            auto* engine = qmlEngine(this);

            QObject::connect(watcher, &QFutureWatcher<bool>::finished, this, [=]() {
                if (watcher->result()) {
                    if (onSaved.isCallable()) {
                        QJSValueList args = { QJSValue(path.toLocalFile()) };
                        if (engine) {
                            args << engine->toScriptValue(QVariant::fromValue(path));
                        }
                        onSaved.call(args);
                    }
                } else {
                    qCWarning(lcCUtils) << "saveItem: failed to save" << path;
                    if (onFailed.isCallable()) {
                        if (engine) {
                            onFailed.call({ engine->toScriptValue(QVariant::fromValue(path)) });
                        } else {
                            onFailed.call();
                        }
                    }
                }
                watcher->deleteLater();
            });
            watcher->setFuture(future);
        });
}

bool CUtils::copyFile(const QUrl& source, const QUrl& target, bool overwrite) {
    if (!source.isLocalFile()) {
        qCWarning(lcCUtils) << "copyFile: source" << source << "is not a local file";
        return false;
    }
    if (!target.isLocalFile()) {
        qCWarning(lcCUtils) << "copyFile: target" << target << "is not a local file";
        return false;
    }

    if (overwrite && QFile::exists(target.toLocalFile())) {
        if (!QFile::remove(target.toLocalFile())) {
            qCWarning(lcCUtils) << "copyFile: overwrite was specified but failed to remove" << target.toLocalFile();
            return false;
        }
    }

    return QFile::copy(source.toLocalFile(), target.toLocalFile());
}

bool CUtils::deleteFile(const QUrl& path) {
    if (!path.isLocalFile()) {
        qCWarning(lcCUtils) << "deleteFile: path" << path << "is not a local file";
        return false;
    }

    return QFile::remove(path.toLocalFile());
}

QString CUtils::toLocalFile(const QUrl& url) {
    if (!url.isLocalFile()) {
        qCWarning(lcCUtils) << "toLocalFile: given url is not a local file" << url;
        return QString();
    }

    return url.toLocalFile();
}

qreal CUtils::clamp(qreal value, qreal min, qreal max) {
    return qBound(min, value, max);
}

namespace {

// DFS over the visual item tree (childItems), returning the first descendant matching the predicate. Unlike
// QObject::findChild, this walks parentItem/childItems relationships so it traverses the QML visual hierarchy.
template <typename Predicate> QQuickItem* findChildDfs(QQuickItem* root, Predicate&& match) {
    const auto children = root->childItems();
    for (QQuickItem* const child : children) {
        if (match(child)) {
            return child;
        }
        if (QQuickItem* const found = findChildDfs(child, match)) {
            return found;
        }
    }
    return nullptr;
}

// DFS over the visual item tree, appending every descendant matching the predicate to out.
template <typename Predicate> void findChildrenDfs(QQuickItem* root, Predicate&& match, QList<QQuickItem*>& out) {
    const auto children = root->childItems();
    for (QQuickItem* const child : children) {
        if (match(child)) {
            out.append(child);
        }
        findChildrenDfs(child, match, out);
    }
}

} // namespace

QQuickItem* CUtils::findChild(QQuickItem* root, const QString& name) {
    if (!root) {
        return nullptr;
    }

    return findChildDfs(root, [&name](const QQuickItem* item) {
        return item->objectName() == name;
    });
}

QList<QQuickItem*> CUtils::findChildren(QQuickItem* root, const QString& name) {
    QList<QQuickItem*> children;
    if (root) {
        findChildrenDfs(
            root,
            [&name](const QQuickItem* item) {
                return item->objectName() == name;
            },
            children);
    }
    return children;
}

QList<QQuickItem*> CUtils::findChildrenMatching(QQuickItem* root, const QString& pattern) {
    QList<QQuickItem*> children;
    if (root) {
        const QRegularExpression re(pattern);
        findChildrenDfs(
            root,
            [&re](const QQuickItem* item) {
                return re.match(item->objectName()).hasMatch();
            },
            children);
    }
    return children;
}

#ifndef CAELESTIA_VERSION
#define CAELESTIA_VERSION ""
#endif

QString CUtils::version() const {
    return QStringLiteral(CAELESTIA_VERSION);
}

QString CUtils::qtVersion() const {
    return QStringLiteral(QT_VERSION_STR);
}

bool CUtils::loadTranslation(const QString& language) {
    if (!qApp) return false;

    if (s_translator) {
        qApp->removeTranslator(s_translator);
        delete s_translator;
        s_translator = nullptr;
    }

    QString lang = language.trimmed();
    if (lang.isEmpty() || lang == QStringLiteral("auto")) {
        const QString sys = QLocale::system().name();
        lang = sys.startsWith(QStringLiteral("tr"), Qt::CaseInsensitive) ? QStringLiteral("tr") : QStringLiteral("en");
    }

    s_translator = new QTranslator(qApp);

    QString configDir = qEnvironmentVariable("XDG_CONFIG_HOME");
    if (configDir.isEmpty()) {
        configDir = QDir::homePath() + QStringLiteral("/.config");
    }

    QStringList searchDirs = {
        configDir + QStringLiteral("/quickshell/caelestia/i18n"),
        configDir + QStringLiteral("/quickshell/caelestia/translations"),
        QDir::homePath() + QStringLiteral("/.config/quickshell/caelestia/i18n"),
        QDir::homePath() + QStringLiteral("/.config/quickshell/caelestia/translations"),
        QDir::currentPath() + QStringLiteral("/i18n"),
        QDir::currentPath() + QStringLiteral("/translations")
    };

    const QString atomShellDir = qEnvironmentVariable("ATOM_SHELL_DIR");
    if (!atomShellDir.isEmpty()) {
        searchDirs.prepend(atomShellDir + QStringLiteral("/translations"));
        searchDirs.prepend(atomShellDir + QStringLiteral("/i18n"));
    }

    bool loaded = false;
    for (const QString& dir : searchDirs) {
        if (s_translator->load(QStringLiteral("atom-shell_") + lang, dir) ||
            s_translator->load(QStringLiteral("qml_") + lang, dir)) {
            loaded = true;
            break;
        }
    }

    if (loaded) {
        qApp->installTranslator(s_translator);
    } else {
        delete s_translator;
        s_translator = nullptr;
    }

    auto* engine = qmlEngine(this);
    if (engine) engine->retranslate();

    return loaded;
}

} // namespace caelestia
