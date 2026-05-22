// SPDX-License-Identifier: GPL-3.0-only

pub mod compare;
pub mod diff;
mod ffi;
pub mod media;
pub mod report;
pub mod sync;
pub mod transfer;

pub use compare::{
    checksum_file, checksum_file_set, compare_folders, compare_folders_with_progress,
    compare_scans, compare_scans_with_progress, detect_renames, file_count_folder_count_size,
    parse_ignore_patterns, path_buf_string, scan_folder, scan_folder_with_progress, ChecksumMethod,
    CompareMode, CompareReport, CompareTolerance, ComparisonRow, FileChecksums, FileEntry,
    FileStatus, ProgressCallbacks, ProgressEvent, ProgressStage, ScanOptions, ScanResult,
    SymlinkPolicy, CANCELED_MESSAGE,
};
pub use ffi::{
    FfiReport, SfcCancelCallback, SfcCompareMode, SfcCompareRequest, SfcFileStatus,
    SfcProgressCallback, SfcProgressStage,
};
pub use media::{probe as probe_media, MediaInfo, MediaKind};
pub use report::{
    compare_summary, current_timestamp, pass_fail, report_csv, report_txt, write_text,
};
pub use sync::{
    build_plan as build_sync_plan, execute_plan as execute_sync_plan, ConflictStrategy, SyncAction,
    SyncActionKind, SyncMode, SyncOptions, SyncPlan,
};

#[cfg(test)]
mod tests;
