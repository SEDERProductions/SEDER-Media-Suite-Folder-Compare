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
    SFC_COMPARE_PATH_SIZE_CHECKSUM = 2,
    SFC_COMPARE_MEDIA_METADATA = 3,
    SFC_COMPARE_PERCEPTUAL_HASH = 4
} SfcCompareMode;

typedef enum SfcFileStatus {
    SFC_STATUS_MATCHING = 0,
    SFC_STATUS_CHANGED = 1,
    SFC_STATUS_ONLY_IN_A = 2,
    SFC_STATUS_ONLY_IN_B = 3,
    SFC_STATUS_RENAMED = 4
} SfcFileStatus;

typedef enum SfcSyncMode {
    SFC_SYNC_MIRROR_A_TO_B = 0,
    SFC_SYNC_MIRROR_B_TO_A = 1,
    SFC_SYNC_TWO_WAY_NEWER_WINS = 2,
    SFC_SYNC_TWO_WAY_MANUAL = 3
} SfcSyncMode;

typedef enum SfcConflictStrategy {
    SFC_CONFLICT_NEWER_WINS = 0,
    SFC_CONFLICT_LARGER_WINS = 1,
    SFC_CONFLICT_ASK_USER = 2,
    SFC_CONFLICT_SKIP = 3
} SfcConflictStrategy;

typedef enum SfcSyncActionKind {
    SFC_ACTION_COPY = 0,
    SFC_ACTION_DELETE = 1,
    SFC_ACTION_RENAME = 2,
    SFC_ACTION_SKIP = 3
} SfcSyncActionKind;

typedef enum SfcDiffLineKind {
    SFC_DIFF_EQUAL = 0,
    SFC_DIFF_INSERT = 1,
    SFC_DIFF_DELETE = 2
} SfcDiffLineKind;

typedef enum SfcProgressStage {
    SFC_PROGRESS_SCANNING_A = 0,
    SFC_PROGRESS_SCANNING_B = 1,
    SFC_PROGRESS_CHECKSUMMING = 2,
    SFC_PROGRESS_COMPARING = 3,
    SFC_PROGRESS_TRANSFERRING = 4,
    SFC_PROGRESS_COMPLETE = 5,
    SFC_PROGRESS_CANCELED = 6,
    SFC_PROGRESS_FAILED = 7
} SfcProgressStage;

typedef struct SfcReport SfcReport;

typedef struct {
    const char *relative_path;
    SfcFileStatus status;
    bool size_a_present;
    bool size_b_present;
    uint64_t size_a;
    uint64_t size_b;
    const char *checksum_a;
    const char *checksum_b;
} SfcReportRowData;

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
    uint64_t tolerance_mtime_secs;
    uint64_t tolerance_duration_ms;
    uint32_t tolerance_phash_hamming;
    bool follow_symlinks;
    bool detect_renames;
} SfcCompareRequest;

SfcReport *sfc_compare_folders(const SfcCompareRequest *request, char **error_out);
void sfc_report_free(SfcReport *report);
void sfc_string_free(char *value);

size_t sfc_report_row_count(const SfcReport *report);
SfcReportRowData sfc_report_row_get(const SfcReport *report, size_t index);
const char *sfc_report_row_path(const SfcReport *report, size_t index);
SfcFileStatus sfc_report_row_status(const SfcReport *report, size_t index);
bool sfc_report_row_size_a_present(const SfcReport *report, size_t index);
bool sfc_report_row_size_b_present(const SfcReport *report, size_t index);
uint64_t sfc_report_row_size_a(const SfcReport *report, size_t index);
uint64_t sfc_report_row_size_b(const SfcReport *report, size_t index);
const char *sfc_report_row_checksum_a(const SfcReport *report, size_t index);
const char *sfc_report_row_checksum_b(const SfcReport *report, size_t index);

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

// ── Transfer operations ────────────────────────────────────────────────────

bool sfc_copy_file(
    const char *source,
    const char *dest,
    SfcProgressCallback progress,
    SfcCancelCallback cancel,
    void *user_data,
    char **error_out);

bool sfc_copy_folder(
    const char *source,
    const char *dest,
    SfcProgressCallback progress,
    SfcCancelCallback cancel,
    void *user_data,
    char **error_out);

bool sfc_remove_file(const char *path, char **error_out);

bool sfc_remove_folder(const char *path, char **error_out);

// ── Sync plan ──────────────────────────────────────────────────────────────

typedef struct SfcSyncPlan SfcSyncPlan;

SfcSyncPlan *sfc_sync_build_plan(
    const SfcReport *report,
    const char *folder_a,
    const char *folder_b,
    SfcSyncMode mode,
    bool propagate_deletes,
    SfcConflictStrategy conflict,
    char **error_out);

void sfc_sync_plan_free(SfcSyncPlan *plan);
size_t sfc_sync_plan_len(const SfcSyncPlan *plan);
SfcSyncActionKind sfc_sync_plan_action_kind(const SfcSyncPlan *plan, size_t index);
const char *sfc_sync_plan_action_source(const SfcSyncPlan *plan, size_t index);
const char *sfc_sync_plan_action_dest(const SfcSyncPlan *plan, size_t index);
const char *sfc_sync_plan_action_path(const SfcSyncPlan *plan, size_t index);
const char *sfc_sync_plan_action_reason(const SfcSyncPlan *plan, size_t index);

bool sfc_sync_plan_execute(
    const SfcSyncPlan *plan,
    bool dry_run,
    SfcProgressCallback progress,
    SfcCancelCallback cancel,
    void *user_data,
    char **error_out);

// ── Text & hex diff ────────────────────────────────────────────────────────

typedef struct SfcTextDiff SfcTextDiff;

SfcTextDiff *sfc_diff_text(const char *path_a, const char *path_b, char **error_out);
void sfc_text_diff_free(SfcTextDiff *diff);
size_t sfc_text_diff_len(const SfcTextDiff *diff);
SfcDiffLineKind sfc_text_diff_kind(const SfcTextDiff *diff, size_t index);
uint32_t sfc_text_diff_line_a(const SfcTextDiff *diff, size_t index);
uint32_t sfc_text_diff_line_b(const SfcTextDiff *diff, size_t index);
const char *sfc_text_diff_text(const SfcTextDiff *diff, size_t index);

bool sfc_is_text_file(const char *path);

// Caller passes a buffer of `length` bytes; returns number of bytes read (<= length).
size_t sfc_hex_window(const char *path, uint64_t offset, uint8_t *out, size_t length);

#ifdef __cplusplus
}
#endif

#endif
