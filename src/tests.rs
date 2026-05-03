// SPDX-License-Identifier: GPL-3.0-only

use super::*;
use std::cell::Cell;
use std::fs;
use std::path::Path;
use tempfile::tempdir;

fn write(path: &Path, contents: &str) {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).unwrap();
    }
    fs::write(path, contents).unwrap();
}

#[test]
fn recursively_scans_files_and_folders() {
    let dir = tempdir().unwrap();
    write(&dir.path().join("card/a.mov"), "aaa");
    let scan = scan_folder(
        dir.path(),
        &ScanOptions {
            ignore_hidden_system: true,
            ignore_patterns: vec![],
            checksum: false,
        },
    )
    .unwrap();
    assert!(scan.files.contains_key("card/a.mov"));
    assert!(scan.folders.contains("card"));
}

#[test]
fn detects_nested_relative_path_matches() {
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    write(&a.path().join("A001/clip.mov"), "same");
    write(&b.path().join("A001/clip.mov"), "same");
    let report = compare_folders(a.path(), b.path(), CompareMode::PathSize, true, vec![]).unwrap();
    assert_eq!(report.rows[0].relative_path, "A001/clip.mov");
    assert_eq!(report.rows[0].status, FileStatus::Matching);
}

#[test]
fn detects_files_only_in_a_and_b() {
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    write(&a.path().join("only-a.mov"), "a");
    write(&b.path().join("only-b.mov"), "b");
    let report = compare_folders(a.path(), b.path(), CompareMode::PathSize, true, vec![]).unwrap();
    assert!(report
        .rows
        .iter()
        .any(|row| row.status == FileStatus::OnlyInA));
    assert!(report
        .rows
        .iter()
        .any(|row| row.status == FileStatus::OnlyInB));
}

#[test]
fn detects_changed_and_matching_files() {
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    write(&a.path().join("changed.mov"), "a");
    write(&b.path().join("changed.mov"), "bb");
    write(&a.path().join("same.mov"), "ok");
    write(&b.path().join("same.mov"), "ok");
    let report = compare_folders(a.path(), b.path(), CompareMode::PathSize, true, vec![]).unwrap();
    assert!(report
        .rows
        .iter()
        .any(|row| row.relative_path == "changed.mov" && row.status == FileStatus::Changed));
    assert!(report
        .rows
        .iter()
        .any(|row| row.relative_path == "same.mov" && row.status == FileStatus::Matching));
}

#[test]
fn ignores_system_files() {
    let dir = tempdir().unwrap();
    write(&dir.path().join(".DS_Store"), "hidden");
    write(&dir.path().join("clip.mov"), "clip");
    let scan = scan_folder(
        dir.path(),
        &ScanOptions {
            ignore_hidden_system: true,
            ignore_patterns: vec![],
            checksum: false,
        },
    )
    .unwrap();
    assert!(!scan.files.contains_key(".DS_Store"));
    assert!(scan.files.contains_key("clip.mov"));
}

#[test]
fn supports_bare_and_glob_ignore_patterns() {
    let dir = tempdir().unwrap();
    write(&dir.path().join("clip.mov"), "clip");
    write(&dir.path().join("cache/render.tmp"), "tmp");
    write(&dir.path().join("proxy/clip.mov"), "proxy");
    let scan = scan_folder(
        dir.path(),
        &ScanOptions {
            ignore_hidden_system: true,
            ignore_patterns: vec!["*.tmp,proxy".into()],
            checksum: false,
        },
    )
    .unwrap();
    assert!(scan.files.contains_key("clip.mov"));
    assert!(!scan.files.contains_key("cache/render.tmp"));
    assert!(!scan.files.contains_key("proxy/clip.mov"));
}

#[test]
fn checksum_comparison_detects_same_size_changes() {
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    write(&a.path().join("clip.mov"), "abcd");
    write(&b.path().join("clip.mov"), "wxyz");
    let report = compare_folders(
        a.path(),
        b.path(),
        CompareMode::PathSizeChecksum,
        true,
        vec![],
    )
    .unwrap();
    assert_eq!(report.rows[0].status, FileStatus::Changed);
    assert!(report.rows[0].checksum_a.is_some());
    assert!(report.rows[0].xxh64_a.is_some());
}

#[test]
fn progress_reports_scan_checksum_compare_and_complete() {
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    write(&a.path().join("clip.mov"), "abcd");
    write(&b.path().join("clip.mov"), "abcd");
    let mut stages = Vec::new();
    {
        let mut progress = |event: ProgressEvent| stages.push(event.stage);
        let cancel = || false;
        let mut callbacks = ProgressCallbacks {
            progress: Some(&mut progress),
            cancel: Some(&cancel),
        };
        compare_folders_with_progress(
            a.path(),
            b.path(),
            CompareMode::PathSizeChecksum,
            true,
            vec![],
            &mut callbacks,
        )
        .unwrap();
    }

    assert!(stages.contains(&ProgressStage::ScanningA));
    assert!(stages.contains(&ProgressStage::ScanningB));
    assert!(stages.contains(&ProgressStage::Checksumming));
    assert!(stages.contains(&ProgressStage::Comparing));
    assert!(stages.contains(&ProgressStage::Complete));
}

#[test]
fn comparison_can_be_canceled() {
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    write(&a.path().join("clip.mov"), "abcd");
    write(&b.path().join("clip.mov"), "abcd");
    let cancel_calls = Cell::new(0);
    let cancel = || {
        cancel_calls.set(cancel_calls.get() + 1);
        true
    };
    let mut callbacks = ProgressCallbacks {
        progress: None,
        cancel: Some(&cancel),
    };
    let error = compare_folders_with_progress(
        a.path(),
        b.path(),
        CompareMode::PathSizeChecksum,
        true,
        vec![],
        &mut callbacks,
    )
    .unwrap_err();
    assert!(error.to_string().contains(CANCELED_MESSAGE));
    assert!(cancel_calls.get() > 0);
}

#[test]
fn empty_folders_compare_cleanly() {
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    let report = compare_folders(a.path(), b.path(), CompareMode::PathSize, true, vec![]).unwrap();
    assert!(report.rows.is_empty());
    assert_eq!(pass_fail(&report), "PASS");
}

#[test]
fn long_paths_remain_relative_and_exportable() {
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    let rel = "A001/very/long/path/that/keeps/going/clip_with_a_long_descriptive_name.mov";
    write(&a.path().join(rel), "same");
    write(&b.path().join(rel), "same");
    let report = compare_folders(a.path(), b.path(), CompareMode::PathSize, true, vec![]).unwrap();
    assert_eq!(report.rows[0].relative_path, rel);
    assert!(report_txt(&report, "Folder Compare").contains(rel));
}

#[test]
fn timestamp_is_iso8601_shape() {
    use crate::report::current_timestamp;
    let ts = current_timestamp();
    // Guard the shape: YYYY-MM-DDTHH:MM:SSZ
    assert_eq!(ts.len(), 20, "expected 20 chars, got {ts:?}");
    assert_eq!(&ts[4..5], "-");
    assert_eq!(&ts[7..8], "-");
    assert_eq!(&ts[10..11], "T");
    assert_eq!(&ts[13..14], ":");
    assert_eq!(&ts[16..17], ":");
    assert_eq!(&ts[19..20], "Z");
    assert!(ts.starts_with("20"));
    assert!(!ts.contains("unix:"));
}

#[test]
fn ignore_literal_no_substring_match() {
    let dir = tempdir().unwrap();
    write(&dir.path().join("nodejs/script.js"), "x");
    let scan = scan_folder(
        dir.path(),
        &ScanOptions {
            ignore_hidden_system: false,
            // Pattern "node" must NOT match file "script.js" inside the
            // "nodejs" folder — only basename equality, never substring.
            ignore_patterns: vec!["node".into()],
            checksum: false,
        },
    )
    .unwrap();
    assert!(scan.files.contains_key("nodejs/script.js"));
}

#[test]
fn ignore_glob_matches_pattern() {
    let dir = tempdir().unwrap();
    write(&dir.path().join("nodejs/script.js"), "x");
    let scan = scan_folder(
        dir.path(),
        &ScanOptions {
            ignore_hidden_system: false,
            ignore_patterns: vec!["*node*".into()],
            checksum: false,
        },
    )
    .unwrap();
    assert!(!scan.files.contains_key("nodejs/script.js"));
}

#[test]
fn progress_events_for_100_files_are_dense() {
    let dir = tempdir().unwrap();
    for i in 0..100 {
        write(&dir.path().join(format!("clip-{i:03}.mov")), "x");
    }
    let mut events: u64 = 0;
    let mut progress = |_event: ProgressEvent| {
        events += 1;
    };
    let cancel = || false;
    let mut callbacks = ProgressCallbacks {
        progress: Some(&mut progress),
        cancel: Some(&cancel),
    };
    scan_folder_with_progress(
        dir.path(),
        &ScanOptions {
            ignore_hidden_system: true,
            ignore_patterns: vec![],
            checksum: false,
        },
        ProgressStage::ScanningA,
        &mut callbacks,
    )
    .unwrap();
    // Pre-fix: 10 events. Post-fix with multiple_of(50) fallback for total=0:
    // ≥5 + every 50th = current<=5 emits 5; then 50, 100. Plus initial root
    // emit. Should be at least 8 events.
    assert!(
        events >= 8,
        "expected dense progress events for 100 files, got {events}"
    );
}

#[cfg(unix)]
#[test]
fn symlink_appears_as_file_row() {
    use std::os::unix::fs::symlink;
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    let target = a.path().join("real.mov");
    write(&target, "abcd");
    write(&b.path().join("real.mov"), "abcd");
    symlink(&target, a.path().join("aliased.mov")).unwrap();

    let report = compare_folders(a.path(), b.path(), CompareMode::PathSize, true, vec![]).unwrap();
    assert!(report
        .rows
        .iter()
        .any(|row| row.relative_path == "aliased.mov"));
}

#[test]
fn csv_export_escapes_quotes_and_includes_folder_rows() {
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    write(&a.path().join("A001/clip \"one\".mov"), "abcd");
    write(&b.path().join("A001/clip \"one\".mov"), "abcd");
    fs::create_dir_all(a.path().join("only-folder")).unwrap();
    let report = compare_folders(a.path(), b.path(), CompareMode::PathSize, true, vec![]).unwrap();
    let csv = report_csv(&report);
    assert!(csv.contains("\"A001/clip \"\"one\"\".mov\""));
    assert!(csv.contains("\"FolderOnlyInA\",\"only-folder\""));
}
