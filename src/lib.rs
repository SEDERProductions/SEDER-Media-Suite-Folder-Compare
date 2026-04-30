// SPDX-License-Identifier: GPL-3.0-only

mod compare;
mod ffi;
mod report;

pub use compare::{
    checksum_file, checksum_file_set, compare_folders, compare_folders_with_progress,
    compare_scans, compare_scans_with_progress, file_count_folder_count_size,
    parse_ignore_patterns, path_buf_string, scan_folder, scan_folder_with_progress, ChecksumMethod,
    CompareMode, CompareReport, ComparisonRow, FileChecksums, FileEntry, FileStatus,
    ProgressCallbacks, ProgressEvent, ProgressStage, ScanOptions, ScanResult, CANCELED_MESSAGE,
};
pub use ffi::{
    FfiReport, SfcCancelCallback, SfcCompareMode, SfcCompareRequest, SfcFileStatus,
    SfcProgressCallback, SfcProgressStage,
};
pub use report::{
    compare_summary, current_timestamp, pass_fail, report_csv, report_txt, write_text,
};

#[cfg(test)]
mod tests;
