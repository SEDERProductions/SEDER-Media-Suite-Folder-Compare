// SPDX-License-Identifier: GPL-3.0-only

use super::*;
use filetime::FileTime;
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

            probe_media: false,
            symlink_policy: SymlinkPolicy::FollowInTreeOnly,
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

            probe_media: false,
            symlink_policy: SymlinkPolicy::FollowInTreeOnly,
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

            probe_media: false,
            symlink_policy: SymlinkPolicy::FollowInTreeOnly,
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
}

#[test]
fn modified_time_comparison_detects_difference() {
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    write(&a.path().join("same.mov"), "abcd");
    write(&b.path().join("same.mov"), "abcd");
    let base_time = FileTime::from_unix_time(1700000000, 0); // 2023-11-14
    filetime::set_file_times(a.path().join("same.mov"), base_time, base_time).unwrap();
    filetime::set_file_times(b.path().join("same.mov"), base_time, base_time).unwrap();

    write(&a.path().join("changed.mov"), "wxyz");
    write(&b.path().join("changed.mov"), "wxyz");
    filetime::set_file_times(a.path().join("changed.mov"), base_time, base_time).unwrap();
    let later_time = FileTime::from_unix_time(1700003600, 0); // 1 hour later
    filetime::set_file_times(b.path().join("changed.mov"), later_time, later_time).unwrap();

    let report = compare_folders(
        a.path(),
        b.path(),
        CompareMode::PathSizeModified,
        true,
        vec![],
    )
    .unwrap();
    assert_eq!(report.rows.len(), 2);

    let same = report
        .rows
        .iter()
        .find(|r| r.relative_path == "same.mov")
        .unwrap();
    assert_eq!(same.status, FileStatus::Matching);

    let changed = report
        .rows
        .iter()
        .find(|r| r.relative_path == "changed.mov")
        .unwrap();
    assert_eq!(changed.status, FileStatus::Changed);
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
            CompareTolerance::default(),
            false,
            false,
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
        CompareTolerance::default(),
        false,
        false,
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

            probe_media: false,
            symlink_policy: SymlinkPolicy::FollowInTreeOnly,
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

            probe_media: false,
            symlink_policy: SymlinkPolicy::FollowInTreeOnly,
        },
    )
    .unwrap();
    assert!(!scan.files.contains_key("nodejs/script.js"));
}

#[test]
fn ignore_exact_relative_path_without_substring_matching() {
    let dir = tempdir().unwrap();
    write(&dir.path().join("cache/render.tmp"), "tmp");
    write(&dir.path().join("other/render.tmp"), "keep");
    let scan = scan_folder(
        dir.path(),
        &ScanOptions {
            ignore_hidden_system: false,
            ignore_patterns: vec!["cache/render.tmp".into()],
            checksum: false,

            probe_media: false,
            symlink_policy: SymlinkPolicy::FollowInTreeOnly,
        },
    )
    .unwrap();
    assert!(!scan.files.contains_key("cache/render.tmp"));
    assert!(scan.files.contains_key("other/render.tmp"));
}

#[test]
fn report_total_size_saturates_on_overflow() {
    let left = ScanResult {
        total_size: u64::MAX,
        ..Default::default()
    };
    let right = ScanResult {
        total_size: 1,
        ..Default::default()
    };
    let report = compare_scans(&left, &right, CompareMode::PathSize);
    assert_eq!(report.total_size, u64::MAX);
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

            probe_media: false,
            symlink_policy: SymlinkPolicy::FollowInTreeOnly,
        },
        ProgressStage::ScanningA,
        &mut callbacks,
    )
    .unwrap();
    // With multiple_of(10) fallback for total=0:
    // ≥5 + every 10th = current<=5 emits 5; then 10,20,...,100.
    // Plus initial root emit. Should be well above 8 events.
    assert!(
        events >= 8,
        "expected dense progress events for 100 files, got {events}"
    );
}

#[cfg(unix)]
#[test]
fn symlink_to_in_tree_file_is_followed() {
    use std::os::unix::fs::symlink;
    let root = tempdir().unwrap();
    let target = root.path().join("real.mov");
    write(&target, "abcd");
    symlink(&target, root.path().join("aliased.mov")).unwrap();

    let scan = scan_folder(
        root.path(),
        &ScanOptions {
            ignore_hidden_system: true,
            ignore_patterns: vec![],
            checksum: false,
            probe_media: false,
            symlink_policy: SymlinkPolicy::FollowInTreeOnly,
        },
    )
    .unwrap();
    assert!(scan.files.contains_key("aliased.mov"));
    assert!(scan.files["aliased.mov"].is_symlink);
}

#[cfg(unix)]
#[test]
fn symlink_to_out_of_tree_file_is_rejected_in_tree_policy() {
    use std::os::unix::fs::symlink;
    let root = tempdir().unwrap();
    let outside = tempdir().unwrap();
    let target = outside.path().join("outside.mov");
    write(&target, "abcd");
    symlink(&target, root.path().join("outside-link.mov")).unwrap();

    let scan = scan_folder(
        root.path(),
        &ScanOptions {
            ignore_hidden_system: true,
            ignore_patterns: vec![],
            checksum: false,
            probe_media: false,
            symlink_policy: SymlinkPolicy::FollowInTreeOnly,
        },
    )
    .unwrap();
    assert!(!scan.files.contains_key("outside-link.mov"));
}

#[cfg(unix)]
#[test]
fn symlink_to_directory_is_recorded_as_folder() {
    use std::os::unix::fs::symlink;
    let root = tempdir().unwrap();
    let folder = root.path().join("real_dir");
    fs::create_dir_all(&folder).unwrap();
    symlink(&folder, root.path().join("dir-link")).unwrap();
    let scan = scan_folder(
        root.path(),
        &ScanOptions {
            ignore_hidden_system: true,
            ignore_patterns: vec![],
            checksum: false,
            probe_media: false,
            symlink_policy: SymlinkPolicy::FollowInTreeOnly,
        },
    )
    .unwrap();
    assert!(scan.folders.contains("dir-link"));
    assert!(!scan.files.contains_key("dir-link"));
}

#[cfg(unix)]
#[test]
fn preserve_as_link_keeps_symlink_entry() {
    use std::os::unix::fs::symlink;
    let root = tempdir().unwrap();
    let target = root.path().join("real.mov");
    write(&target, "abcd");
    symlink(&target, root.path().join("preserved.mov")).unwrap();

    let scan = scan_folder(
        root.path(),
        &ScanOptions {
            ignore_hidden_system: true,
            ignore_patterns: vec![],
            checksum: false,
            probe_media: false,
            symlink_policy: SymlinkPolicy::PreserveAsLink,
        },
    )
    .unwrap();

    assert!(scan.files.contains_key("preserved.mov"));
    assert!(scan.files["preserved.mov"].is_symlink);
}

#[cfg(unix)]
#[test]
fn broken_symlink_is_skipped() {
    use std::os::unix::fs::symlink;
    let root = tempdir().unwrap();
    symlink(
        root.path().join("missing-target.mov"),
        root.path().join("broken.mov"),
    )
    .unwrap();
    let scan = scan_folder(
        root.path(),
        &ScanOptions {
            ignore_hidden_system: true,
            ignore_patterns: vec![],
            checksum: false,
            probe_media: false,
            symlink_policy: SymlinkPolicy::FollowInTreeOnly,
        },
    )
    .unwrap();
    assert!(!scan.files.contains_key("broken.mov"));
}

#[cfg(unix)]
#[test]
fn copy_folder_allows_symlink_target_inside_root() {
    use crate::transfer::copy_folder;
    use std::os::unix::fs::symlink;

    let src = tempdir().unwrap();
    let dest = tempdir().unwrap();
    write(&src.path().join("real.mov"), "abcd");
    symlink("real.mov", src.path().join("inside-link.mov")).unwrap();

    let mut events: Vec<(ProgressStage, u64, u64, String)> = Vec::new();
    let mut progress = |event: ProgressEvent| {
        events.push((
            event.stage,
            event.current,
            event.total,
            event.path.unwrap_or_default(),
        ));
    };
    let cancel = || false;
    let mut callbacks = ProgressCallbacks {
        progress: Some(&mut progress),
        cancel: Some(&cancel),
    };

    copy_folder(src.path(), dest.path(), &mut callbacks).unwrap();
    assert_eq!(
        fs::read_to_string(dest.path().join("inside-link.mov")).unwrap(),
        "abcd"
    );

    assert_eq!(events.len(), 2);
    assert!(events
        .iter()
        .all(|(stage, _, _, _)| *stage == ProgressStage::Transferring));
    assert_eq!(events[0].1, 1);
    assert_eq!(events[1].1, 2);
    assert!(events.iter().all(|(_, _, total, _)| *total == 2));
}

#[cfg(unix)]
#[test]
fn copy_folder_rejects_symlink_target_outside_root() {
    use crate::transfer::copy_folder;
    use std::os::unix::fs::symlink;

    let src = tempdir().unwrap();
    let dest = tempdir().unwrap();
    let outside = tempdir().unwrap();
    let outside_file = outside.path().join("outside.mov");
    write(&outside_file, "nope");
    symlink(&outside_file, src.path().join("outside-link.mov")).unwrap();

    let mut callbacks = ProgressCallbacks {
        progress: None,
        cancel: None,
    };
    let err = copy_folder(src.path(), dest.path(), &mut callbacks).unwrap_err();
    let msg = err.to_string();
    assert!(msg.contains("outside-link.mov"));
    assert!(msg.contains("outside the source root"));
}

#[cfg(unix)]
#[test]
fn copy_folder_rejects_broken_symlink_deterministically() {
    use crate::transfer::copy_folder;
    use std::os::unix::fs::symlink;

    let src = tempdir().unwrap();
    let dest = tempdir().unwrap();
    symlink("missing.mov", src.path().join("broken-link.mov")).unwrap();

    let mut callbacks = ProgressCallbacks {
        progress: None,
        cancel: None,
    };
    let err = copy_folder(src.path(), dest.path(), &mut callbacks).unwrap_err();
    let msg = err.to_string();
    assert!(msg.contains("broken-link.mov"));
    assert!(msg.contains("missing or broken"));
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

#[test]
fn modified_time_within_tolerance_is_matching() {
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    write(&a.path().join("clip.mov"), "abcd");
    write(&b.path().join("clip.mov"), "abcd");
    let t = FileTime::from_unix_time(1_700_000_000, 0);
    filetime::set_file_times(a.path().join("clip.mov"), t, t).unwrap();
    let t2 = FileTime::from_unix_time(1_700_000_001, 0); // 1s drift
    filetime::set_file_times(b.path().join("clip.mov"), t2, t2).unwrap();

    let mut cb = ProgressCallbacks::default();
    let report = compare_folders_with_progress(
        a.path(),
        b.path(),
        CompareMode::PathSizeModified,
        true,
        vec![],
        CompareTolerance {
            mtime_secs: 5,
            ..CompareTolerance::default()
        },
        false,
        false,
        &mut cb,
    )
    .unwrap();
    assert_eq!(report.rows[0].status, FileStatus::Matching);
}

#[test]
fn rename_detection_reclassifies_only_a_only_b_pair() {
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    write(&a.path().join("old-name.mov"), "samebytes");
    write(&b.path().join("new-name.mov"), "samebytes");

    let mut cb = ProgressCallbacks::default();
    let report = compare_folders_with_progress(
        a.path(),
        b.path(),
        CompareMode::PathSizeChecksum,
        true,
        vec![],
        CompareTolerance::default(),
        false,
        true,
        &mut cb,
    )
    .unwrap();

    assert!(
        report.rows.iter().any(|r| r.status == FileStatus::Renamed),
        "expected a renamed row, got: {:?}",
        report
            .rows
            .iter()
            .map(|r| (&r.relative_path, &r.status))
            .collect::<Vec<_>>()
    );
    let renamed = report
        .rows
        .iter()
        .find(|r| r.status == FileStatus::Renamed)
        .unwrap();
    assert_eq!(renamed.rename_from.as_deref(), Some("old-name.mov"));
    assert_eq!(renamed.rename_to.as_deref(), Some("new-name.mov"));
}

#[test]
fn sync_plan_mirror_a_to_b_copies_missing_and_optionally_deletes() {
    use crate::sync::{build_plan, SyncActionKind, SyncMode, SyncOptions};
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    write(&a.path().join("in-a.mov"), "x");
    write(&b.path().join("in-b.mov"), "x");

    let report = compare_folders(a.path(), b.path(), CompareMode::PathSize, true, vec![]).unwrap();
    let plan = build_plan(
        &report,
        a.path(),
        b.path(),
        SyncMode::MirrorAToB,
        &SyncOptions {
            propagate_deletes: true,
            ..SyncOptions::default()
        },
    );
    let kinds: Vec<_> = plan.actions.iter().map(|a| a.kind).collect();
    assert!(kinds.contains(&SyncActionKind::Copy));
    assert!(kinds.contains(&SyncActionKind::Delete));

    let plan_no_delete = build_plan(
        &report,
        a.path(),
        b.path(),
        SyncMode::MirrorAToB,
        &SyncOptions {
            propagate_deletes: false,
            ..SyncOptions::default()
        },
    );
    assert!(plan_no_delete
        .actions
        .iter()
        .all(|a| a.kind != SyncActionKind::Delete));
}

#[test]
fn sync_dry_run_does_not_touch_disk() {
    use crate::sync::{build_plan, execute_plan, SyncMode, SyncOptions};
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    write(&a.path().join("only-a.mov"), "x");

    let report = compare_folders(a.path(), b.path(), CompareMode::PathSize, true, vec![]).unwrap();
    let options = SyncOptions {
        propagate_deletes: false,
        dry_run: true,
        ..SyncOptions::default()
    };
    let plan = build_plan(&report, a.path(), b.path(), SyncMode::MirrorAToB, &options);
    let mut cb = ProgressCallbacks::default();
    execute_plan(&plan, &options, &mut cb).unwrap();
    assert!(!b.path().join("only-a.mov").exists());
}

#[test]
fn sync_real_run_copies_files() {
    use crate::sync::{build_plan, execute_plan, SyncMode, SyncOptions};
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    write(&a.path().join("only-a.mov"), "hello");

    let report = compare_folders(a.path(), b.path(), CompareMode::PathSize, true, vec![]).unwrap();
    let options = SyncOptions {
        propagate_deletes: false,
        dry_run: false,
        ..SyncOptions::default()
    };
    let plan = build_plan(&report, a.path(), b.path(), SyncMode::MirrorAToB, &options);
    let mut cb = ProgressCallbacks::default();
    execute_plan(&plan, &options, &mut cb).unwrap();
    assert_eq!(fs::read(b.path().join("only-a.mov")).unwrap(), b"hello");
}

#[test]
fn diff_text_detects_inserted_line() {
    use crate::diff::{diff_text, is_text_file, LineKind};
    let a = tempdir().unwrap();
    let b = tempdir().unwrap();
    let ap = a.path().join("a.txt");
    let bp = b.path().join("b.txt");
    fs::write(&ap, "one\ntwo\nthree\n").unwrap();
    fs::write(&bp, "one\ntwo\nINSERTED\nthree\n").unwrap();
    assert!(is_text_file(&ap));
    let hunks = diff_text(&ap, &bp).unwrap();
    assert!(hunks
        .iter()
        .any(|h| h.kind == LineKind::Insert && h.text == "INSERTED"));
}

#[test]
fn hex_window_reads_partial_file() {
    use crate::diff::hex_window;
    let dir = tempdir().unwrap();
    let p = dir.path().join("bin");
    fs::write(&p, b"abcdefghij").unwrap();
    let window = hex_window(&p, 2, 4).unwrap();
    assert_eq!(window, b"cdef");
    let past = hex_window(&p, 8, 100).unwrap();
    assert_eq!(past, b"ij");
}

#[test]
fn copy_file_cancellation_keeps_existing_destination_unchanged() {
    use crate::transfer::copy_file;

    let dir = tempdir().unwrap();
    let source = dir.path().join("source.bin");
    let dest = dir.path().join("dest.bin");

    fs::write(&source, vec![b'a'; 256 * 1024]).unwrap();
    fs::write(&dest, "original-destination").unwrap();

    let cancel = || true;
    let mut callbacks = ProgressCallbacks {
        progress: None,
        cancel: Some(&cancel),
    };

    let err = copy_file(&source, &dest, &mut callbacks).unwrap_err();
    assert!(err.to_string().contains(CANCELED_MESSAGE));
    assert_eq!(fs::read_to_string(&dest).unwrap(), "original-destination");
}

#[test]
#[cfg(unix)]
fn copy_file_write_error_keeps_existing_destination_unchanged() {
    use crate::transfer::copy_file;
    use std::os::unix::fs::PermissionsExt;

    let dir = tempdir().unwrap();
    let source = dir.path().join("source.bin");
    let locked_dir = dir.path().join("locked");
    fs::create_dir_all(&locked_dir).unwrap();
    let dest = locked_dir.join("dest.bin");
    fs::write(&source, "new-content").unwrap();
    fs::write(&dest, "original-destination").unwrap();

    fs::set_permissions(&locked_dir, fs::Permissions::from_mode(0o555)).unwrap();

    let mut callbacks = ProgressCallbacks::default();
    let result = copy_file(&source, &dest, &mut callbacks);

    // Restore permissions for cleanup
    let _ = fs::set_permissions(&locked_dir, fs::Permissions::from_mode(0o755));

    // If copy succeeded, we're likely running as root (which bypasses permission checks).
    // Skip the assertion phase of the test since it relies on permission enforcement.
    if result.is_ok() {
        return;
    }

    let err = result.unwrap_err();
    assert!(
        err.to_string()
            .contains("Failed to create temporary destination")
            || err.to_string().contains("Permission denied")
    );
    assert_eq!(fs::read_to_string(&dest).unwrap(), "original-destination");
}
