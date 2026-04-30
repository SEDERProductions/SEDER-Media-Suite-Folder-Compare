// SPDX-License-Identifier: GPL-3.0-only

use crate::compare::{
    compare_folders_with_progress, CompareMode, CompareReport, FileStatus, ProgressCallbacks,
    ProgressEvent, ProgressStage, CANCELED_MESSAGE,
};
use crate::report::{compare_summary, report_csv, report_txt, write_text};
use anyhow::Result;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::path::Path;
use std::ptr;

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub enum SfcCompareMode {
    PathSize = 0,
    PathSizeModified = 1,
    PathSizeChecksum = 2,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub enum SfcFileStatus {
    Matching = 0,
    Changed = 1,
    OnlyInA = 2,
    OnlyInB = 3,
}

#[repr(C)]
#[derive(Debug, Clone, Copy)]
pub enum SfcProgressStage {
    ScanningA = 0,
    ScanningB = 1,
    Checksumming = 2,
    Comparing = 3,
    Complete = 4,
    Canceled = 5,
    Failed = 6,
}

pub type SfcProgressCallback = Option<
    extern "C" fn(
        stage: SfcProgressStage,
        current: u64,
        total: u64,
        path: *const c_char,
        user_data: *mut c_void,
    ),
>;

pub type SfcCancelCallback = Option<extern "C" fn(user_data: *mut c_void) -> bool>;

#[repr(C)]
pub struct SfcCompareRequest {
    pub folder_a: *const c_char,
    pub folder_b: *const c_char,
    pub mode: SfcCompareMode,
    pub ignore_hidden_system: bool,
    pub ignore_patterns: *const c_char,
    pub progress: SfcProgressCallback,
    pub cancel: SfcCancelCallback,
    pub user_data: *mut c_void,
}

struct FfiRow {
    relative_path: CString,
    status: SfcFileStatus,
    size_a: Option<u64>,
    size_b: Option<u64>,
    checksum_a: Option<CString>,
    checksum_b: Option<CString>,
    xxh64_a: Option<CString>,
    xxh64_b: Option<CString>,
}

pub struct FfiReport {
    report: CompareReport,
    rows: Vec<FfiRow>,
    folders_only_in_a: Vec<CString>,
    folders_only_in_b: Vec<CString>,
    summary: (usize, usize, usize, usize),
}

fn compare_mode_from_ffi(mode: SfcCompareMode) -> CompareMode {
    match mode {
        SfcCompareMode::PathSize => CompareMode::PathSize,
        SfcCompareMode::PathSizeModified => CompareMode::PathSizeModified,
        SfcCompareMode::PathSizeChecksum => CompareMode::PathSizeChecksum,
    }
}

fn file_status_to_ffi(status: &FileStatus) -> SfcFileStatus {
    match status {
        FileStatus::Matching => SfcFileStatus::Matching,
        FileStatus::Changed => SfcFileStatus::Changed,
        FileStatus::OnlyInA => SfcFileStatus::OnlyInA,
        FileStatus::OnlyInB => SfcFileStatus::OnlyInB,
    }
}

fn progress_stage_to_ffi(stage: ProgressStage) -> SfcProgressStage {
    match stage {
        ProgressStage::ScanningA => SfcProgressStage::ScanningA,
        ProgressStage::ScanningB => SfcProgressStage::ScanningB,
        ProgressStage::Checksumming => SfcProgressStage::Checksumming,
        ProgressStage::Comparing => SfcProgressStage::Comparing,
        ProgressStage::Complete => SfcProgressStage::Complete,
        ProgressStage::Canceled => SfcProgressStage::Canceled,
        ProgressStage::Failed => SfcProgressStage::Failed,
    }
}

fn sanitized_cstring(value: &str) -> CString {
    CString::new(value.replace('\0', "")).unwrap_or_else(|_| CString::new("").unwrap())
}

fn string_to_c(value: impl AsRef<str>) -> *mut c_char {
    sanitized_cstring(value.as_ref()).into_raw()
}

unsafe fn cstr_to_string(value: *const c_char, name: &str) -> Result<String> {
    if value.is_null() {
        anyhow::bail!("{name} is required");
    }
    Ok(unsafe { CStr::from_ptr(value) }
        .to_string_lossy()
        .to_string())
}

unsafe fn optional_cstr_to_string(value: *const c_char) -> String {
    if value.is_null() {
        String::new()
    } else {
        unsafe { CStr::from_ptr(value) }
            .to_string_lossy()
            .to_string()
    }
}

unsafe fn set_error(error_out: *mut *mut c_char, message: impl AsRef<str>) {
    if !error_out.is_null() {
        unsafe {
            *error_out = string_to_c(message);
        }
    }
}

fn emit_ffi_progress(callback: SfcProgressCallback, user_data: *mut c_void, event: ProgressEvent) {
    let Some(callback) = callback else {
        return;
    };
    let path = event.path.as_deref().map(sanitized_cstring);
    callback(
        progress_stage_to_ffi(event.stage),
        event.current,
        event.total,
        path.as_ref()
            .map(|value| value.as_ptr())
            .unwrap_or(ptr::null()),
        user_data,
    );
}

fn ffi_report(report: CompareReport) -> *mut FfiReport {
    let rows = report
        .rows
        .iter()
        .map(|row| FfiRow {
            relative_path: sanitized_cstring(&row.relative_path),
            status: file_status_to_ffi(&row.status),
            size_a: row.size_a,
            size_b: row.size_b,
            checksum_a: row.checksum_a.as_deref().map(sanitized_cstring),
            checksum_b: row.checksum_b.as_deref().map(sanitized_cstring),
            xxh64_a: row.xxh64_a.as_deref().map(sanitized_cstring),
            xxh64_b: row.xxh64_b.as_deref().map(sanitized_cstring),
        })
        .collect();
    let folders_only_in_a = report
        .folders_only_in_a
        .iter()
        .map(|path| sanitized_cstring(path))
        .collect();
    let folders_only_in_b = report
        .folders_only_in_b
        .iter()
        .map(|path| sanitized_cstring(path))
        .collect();

    let summary = compare_summary(&report);
    Box::into_raw(Box::new(FfiReport {
        report,
        rows,
        folders_only_in_a,
        folders_only_in_b,
        summary,
    }))
}

unsafe fn report_ref<'a>(report: *const FfiReport) -> Option<&'a FfiReport> {
    unsafe { report.as_ref() }
}

#[no_mangle]
pub unsafe extern "C" fn sfc_compare_folders(
    request: *const SfcCompareRequest,
    error_out: *mut *mut c_char,
) -> *mut FfiReport {
    if request.is_null() {
        unsafe {
            set_error(error_out, "Compare request is required");
        }
        return ptr::null_mut();
    }

    let request = unsafe { &*request };
    let folder_a = match unsafe { cstr_to_string(request.folder_a, "Folder A") } {
        Ok(value) => value,
        Err(error) => {
            unsafe {
                set_error(error_out, error.to_string());
            }
            return ptr::null_mut();
        }
    };
    let folder_b = match unsafe { cstr_to_string(request.folder_b, "Folder B") } {
        Ok(value) => value,
        Err(error) => {
            unsafe {
                set_error(error_out, error.to_string());
            }
            return ptr::null_mut();
        }
    };
    let ignore_patterns = unsafe { optional_cstr_to_string(request.ignore_patterns) };
    let progress = request.progress;
    let cancel = request.cancel;
    let user_data_value = request.user_data;

    let mut progress_callback = |event: ProgressEvent| {
        emit_ffi_progress(progress, user_data_value, event);
    };
    let cancel_callback = || {
        cancel
            .map(|callback| callback(user_data_value))
            .unwrap_or(false)
    };
    let mut callbacks = ProgressCallbacks {
        progress: Some(&mut progress_callback),
        cancel: Some(&cancel_callback),
    };

    match compare_folders_with_progress(
        Path::new(&folder_a),
        Path::new(&folder_b),
        compare_mode_from_ffi(request.mode),
        request.ignore_hidden_system,
        vec![ignore_patterns],
        &mut callbacks,
    ) {
        Ok(report) => ffi_report(report),
        Err(error) => {
            let message = error.to_string();
            let stage = if message.contains(CANCELED_MESSAGE) {
                ProgressStage::Canceled
            } else {
                ProgressStage::Failed
            };
            emit_ffi_progress(
                progress,
                user_data_value as *mut c_void,
                ProgressEvent {
                    stage,
                    current: 0,
                    total: 0,
                    path: Some(message.clone()),
                },
            );
            unsafe {
                set_error(error_out, message);
            }
            ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_free(report: *mut FfiReport) {
    if !report.is_null() {
        drop(unsafe { Box::from_raw(report) });
    }
}

#[no_mangle]
pub unsafe extern "C" fn sfc_string_free(value: *mut c_char) {
    if !value.is_null() {
        drop(unsafe { CString::from_raw(value) });
    }
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_row_count(report: *const FfiReport) -> usize {
    unsafe { report_ref(report) }
        .map(|report| report.rows.len())
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_folder_count(report: *const FfiReport, side: u32) -> usize {
    unsafe { report_ref(report) }
        .map(|report| match side {
            0 => report.folders_only_in_a.len(),
            1 => report.folders_only_in_b.len(),
            _ => 0,
        })
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_folder_path(
    report: *const FfiReport,
    side: u32,
    index: usize,
) -> *const c_char {
    let Some(report) = (unsafe { report_ref(report) }) else {
        return ptr::null();
    };
    match side {
        0 => report
            .folders_only_in_a
            .get(index)
            .map(|value| value.as_ptr())
            .unwrap_or(ptr::null()),
        1 => report
            .folders_only_in_b
            .get(index)
            .map(|value| value.as_ptr())
            .unwrap_or(ptr::null()),
        _ => ptr::null(),
    }
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_row_path(
    report: *const FfiReport,
    index: usize,
) -> *const c_char {
    unsafe { report_ref(report) }
        .and_then(|report| report.rows.get(index))
        .map(|row| row.relative_path.as_ptr())
        .unwrap_or(ptr::null())
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_row_status(
    report: *const FfiReport,
    index: usize,
) -> SfcFileStatus {
    unsafe { report_ref(report) }
        .and_then(|report| report.rows.get(index))
        .map(|row| row.status)
        .unwrap_or(SfcFileStatus::Changed)
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_row_size_a_present(
    report: *const FfiReport,
    index: usize,
) -> bool {
    unsafe { report_ref(report) }
        .and_then(|report| report.rows.get(index))
        .and_then(|row| row.size_a)
        .is_some()
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_row_size_b_present(
    report: *const FfiReport,
    index: usize,
) -> bool {
    unsafe { report_ref(report) }
        .and_then(|report| report.rows.get(index))
        .and_then(|row| row.size_b)
        .is_some()
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_row_size_a(report: *const FfiReport, index: usize) -> u64 {
    unsafe { report_ref(report) }
        .and_then(|report| report.rows.get(index))
        .and_then(|row| row.size_a)
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_row_size_b(report: *const FfiReport, index: usize) -> u64 {
    unsafe { report_ref(report) }
        .and_then(|report| report.rows.get(index))
        .and_then(|row| row.size_b)
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_row_checksum_a(
    report: *const FfiReport,
    index: usize,
) -> *const c_char {
    unsafe { report_ref(report) }
        .and_then(|report| report.rows.get(index))
        .and_then(|row| row.checksum_a.as_ref())
        .map(|value| value.as_ptr())
        .unwrap_or(ptr::null())
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_row_checksum_b(
    report: *const FfiReport,
    index: usize,
) -> *const c_char {
    unsafe { report_ref(report) }
        .and_then(|report| report.rows.get(index))
        .and_then(|row| row.checksum_b.as_ref())
        .map(|value| value.as_ptr())
        .unwrap_or(ptr::null())
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_row_xxh64_a(
    report: *const FfiReport,
    index: usize,
) -> *const c_char {
    unsafe { report_ref(report) }
        .and_then(|report| report.rows.get(index))
        .and_then(|row| row.xxh64_a.as_ref())
        .map(|value| value.as_ptr())
        .unwrap_or(ptr::null())
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_row_xxh64_b(
    report: *const FfiReport,
    index: usize,
) -> *const c_char {
    unsafe { report_ref(report) }
        .and_then(|report| report.rows.get(index))
        .and_then(|row| row.xxh64_b.as_ref())
        .map(|value| value.as_ptr())
        .unwrap_or(ptr::null())
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_total_files(report: *const FfiReport) -> usize {
    unsafe { report_ref(report) }
        .map(|report| report.report.total_files)
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_total_folders(report: *const FfiReport) -> usize {
    unsafe { report_ref(report) }
        .map(|report| report.report.total_folders)
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_total_size(report: *const FfiReport) -> u64 {
    unsafe { report_ref(report) }
        .map(|report| report.report.total_size)
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_matching_count(report: *const FfiReport) -> usize {
    unsafe { report_ref(report) }
        .map(|report| report.summary.3)
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_changed_count(report: *const FfiReport) -> usize {
    unsafe { report_ref(report) }
        .map(|report| report.summary.2)
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_only_a_count(report: *const FfiReport) -> usize {
    unsafe { report_ref(report) }
        .map(|report| report.summary.0)
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_only_b_count(report: *const FfiReport) -> usize {
    unsafe { report_ref(report) }
        .map(|report| report.summary.1)
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_folder_diff_count(report: *const FfiReport) -> usize {
    unsafe { report_ref(report) }
        .map(|report| report.folders_only_in_a.len() + report.folders_only_in_b.len())
        .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_txt(
    report: *const FfiReport,
    title: *const c_char,
) -> *mut c_char {
    let Some(report) = (unsafe { report_ref(report) }) else {
        return ptr::null_mut();
    };
    let title = unsafe { optional_cstr_to_string(title) };
    string_to_c(report_txt(
        &report.report,
        if title.is_empty() {
            "SEDER Media Suite Folder Compare Report"
        } else {
            &title
        },
    ))
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_csv(report: *const FfiReport) -> *mut c_char {
    unsafe { report_ref(report) }
        .map(|report| string_to_c(report_csv(&report.report)))
        .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_write_txt(
    report: *const FfiReport,
    path: *const c_char,
    title: *const c_char,
    error_out: *mut *mut c_char,
) -> bool {
    let Some(report) = (unsafe { report_ref(report) }) else {
        unsafe {
            set_error(error_out, "Report is required");
        }
        return false;
    };
    let path = match unsafe { cstr_to_string(path, "Export path") } {
        Ok(value) => value,
        Err(error) => {
            unsafe {
                set_error(error_out, error.to_string());
            }
            return false;
        }
    };
    let title = unsafe { optional_cstr_to_string(title) };
    match write_text(
        Path::new(&path),
        &report_txt(
            &report.report,
            if title.is_empty() {
                "SEDER Media Suite Folder Compare Report"
            } else {
                &title
            },
        ),
    ) {
        Ok(()) => true,
        Err(error) => {
            unsafe {
                set_error(error_out, error.to_string());
            }
            false
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sfc_report_write_csv(
    report: *const FfiReport,
    path: *const c_char,
    error_out: *mut *mut c_char,
) -> bool {
    let Some(report) = (unsafe { report_ref(report) }) else {
        unsafe {
            set_error(error_out, "Report is required");
        }
        return false;
    };
    let path = match unsafe { cstr_to_string(path, "Export path") } {
        Ok(value) => value,
        Err(error) => {
            unsafe {
                set_error(error_out, error.to_string());
            }
            return false;
        }
    };
    match write_text(Path::new(&path), &report_csv(&report.report)) {
        Ok(()) => true,
        Err(error) => {
            unsafe {
                set_error(error_out, error.to_string());
            }
            false
        }
    }
}
