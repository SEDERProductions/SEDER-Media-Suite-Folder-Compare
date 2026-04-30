// SPDX-License-Identifier: GPL-3.0-only

#ifndef SEDER_FOLDER_COMPARE_H
#define SEDER_FOLDER_COMPARE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum SfcCompareMode {
    SFC_COMPARE_PATH_SIZE = 0,
    SFC_COMPARE_PATH_SIZE_MODIFIED = 1,
    SFC_COMPARE_PATH_SIZE_CHECKSUM = 2
} SfcCompareMode;

typedef enum SfcFileStatus {
    SFC_STATUS_MATCHING = 0,
    SFC_STATUS_CHANGED = 1,
    SFC_STATUS_ONLY_IN_A = 2,
    SFC_STATUS_ONLY_IN_B = 3
} SfcFileStatus;

typedef enum SfcProgressStage {
    SFC_PROGRESS_SCANNING_A = 0,
    SFC_PROGRESS_SCANNING_B = 1,
    SFC_PROGRESS_CHECKSUMMING = 2,
    SFC_PROGRESS_COMPARING = 3,
    SFC_PROGRESS_COMPLETE = 4,
    SFC_PROGRESS_CANCELED = 5,
    SFC_PROGRESS_FAILED = 6
} SfcProgressStage;

typedef struct SfcReport SfcReport;

typedef void (*SfcProgressCallback)(
    SfcProgressStage stage,
    uint64_t current,
    uint64_t total,
    const char *path,
    void *user_data);

typedef bool (*SfcCancelCallback)(void *user_data);

typedef struct SfcCompareRequest {
    const char *folder_a;
    const char *folder_b;
    SfcCompareMode mode;
    bool ignore_hidden_system;
    const char *ignore_patterns;
    SfcProgressCallback progress;
    SfcCancelCallback cancel;
    void *user_data;
} SfcCompareRequest;

SfcReport *sfc_compare_folders(const SfcCompareRequest *request, char **error_out);
void sfc_report_free(SfcReport *report);
void sfc_string_free(char *value);

size_t sfc_report_row_count(const SfcReport *report);
const char *sfc_report_row_path(const SfcReport *report, size_t index);
SfcFileStatus sfc_report_row_status(const SfcReport *report, size_t index);
bool sfc_report_row_size_a_present(const SfcReport *report, size_t index);
bool sfc_report_row_size_b_present(const SfcReport *report, size_t index);
uint64_t sfc_report_row_size_a(const SfcReport *report, size_t index);
uint64_t sfc_report_row_size_b(const SfcReport *report, size_t index);
const char *sfc_report_row_checksum_a(const SfcReport *report, size_t index);
const char *sfc_report_row_checksum_b(const SfcReport *report, size_t index);
const char *sfc_report_row_xxh64_a(const SfcReport *report, size_t index);
const char *sfc_report_row_xxh64_b(const SfcReport *report, size_t index);

size_t sfc_report_folder_count(const SfcReport *report, uint32_t side);
const char *sfc_report_folder_path(const SfcReport *report, uint32_t side, size_t index);

size_t sfc_report_total_files(const SfcReport *report);
size_t sfc_report_total_folders(const SfcReport *report);
uint64_t sfc_report_total_size(const SfcReport *report);
size_t sfc_report_matching_count(const SfcReport *report);
size_t sfc_report_changed_count(const SfcReport *report);
size_t sfc_report_only_a_count(const SfcReport *report);
size_t sfc_report_only_b_count(const SfcReport *report);
size_t sfc_report_folder_diff_count(const SfcReport *report);

char *sfc_report_txt(const SfcReport *report, const char *title);
char *sfc_report_csv(const SfcReport *report);
bool sfc_report_write_txt(
    const SfcReport *report,
    const char *path,
    const char *title,
    char **error_out);
bool sfc_report_write_csv(const SfcReport *report, const char *path, char **error_out);

#ifdef __cplusplus
}
#endif

#endif
