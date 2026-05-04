// SPDX-License-Identifier: GPL-3.0-only

#pragma once

#include "seder_folder_compare.h"

#include <QString>

inline QString takeError(char *error)
{
    if (!error) {
        return {};
    }
    const QString message = QString::fromUtf8(error);
    sfc_string_free(error);
    return message;
}
