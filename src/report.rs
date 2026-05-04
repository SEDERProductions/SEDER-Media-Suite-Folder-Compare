// SPDX-License-Identifier: GPL-3.0-only

use crate::compare::{CompareReport, FileStatus};
use anyhow::{Context, Result};
use std::fs::File;
use std::io::Write;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn current_timestamp() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or_default();
    unix_to_utc_datetime(secs)
}

fn unix_to_utc_datetime(secs: u64) -> String {
    let days = (secs / 86_400) as i64;
    let day_secs = secs % 86_400;
    let (year, month, day) = civil_from_days(days);
    let hour = day_secs / 3_600;
    let minute = (day_secs % 3_600) / 60;
    let second = day_secs % 60;
    format!("{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z")
}

fn civil_from_days(days_since_unix_epoch: i64) -> (i64, u64, u64) {
    let z = days_since_unix_epoch + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = mp + if mp < 10 { 3 } else { -9 };
    let year = y + if m <= 2 { 1 } else { 0 };
    (year, m as u64, d as u64)
}

pub fn pass_fail(report: &CompareReport) -> &'static str {
    if report
        .rows
        .iter()
        .all(|row| row.status == FileStatus::Matching)
        && report.folders_only_in_a.is_empty()
        && report.folders_only_in_b.is_empty()
    {
        "PASS"
    } else {
        "FAIL"
    }
}

pub fn compare_summary(report: &CompareReport) -> (usize, usize, usize, usize) {
    let only_a = report
        .rows
        .iter()
        .filter(|row| row.status == FileStatus::OnlyInA)
        .count();
    let only_b = report
        .rows
        .iter()
        .filter(|row| row.status == FileStatus::OnlyInB)
        .count();
    let changed = report
        .rows
        .iter()
        .filter(|row| row.status == FileStatus::Changed)
        .count();
    let matching = report
        .rows
        .iter()
        .filter(|row| row.status == FileStatus::Matching)
        .count();
    (only_a, only_b, changed, matching)
}

pub fn report_txt(report: &CompareReport, title: &str) -> String {
    let (only_a, only_b, changed, matching) = compare_summary(report);
    let mut out = format!(
        "{title}\nGenerated: {}\nStatus: {}\nTotal files: {}\nTotal folders: {}\nTotal size: {}\nOnly in A: {}\nOnly in B: {}\nChanged: {}\nMatching: {}\n\n",
        current_timestamp(),
        pass_fail(report),
        report.total_files,
        report.total_folders,
        report.total_size,
        only_a,
        only_b,
        changed,
        matching
    );
    for row in &report.rows {
        let status = match row.status {
            FileStatus::Matching => "Matching",
            FileStatus::Changed => "Changed",
            FileStatus::OnlyInA => "Only in A",
            FileStatus::OnlyInB => "Only in B",
        };
        let size_a = row
            .size_a
            .map(|s| s.to_string())
            .unwrap_or_else(|| "—".to_string());
        let size_b = row
            .size_b
            .map(|s| s.to_string())
            .unwrap_or_else(|| "—".to_string());
        out.push_str(&format!(
            "{}\t{}\t{}\t{}\n",
            status, row.relative_path, size_a, size_b
        ));
    }
    for folder in &report.folders_only_in_a {
        out.push_str(&format!("Folder only in A\t{folder}\n"));
    }
    for folder in &report.folders_only_in_b {
        out.push_str(&format!("Folder only in B\t{folder}\n"));
    }
    out
}

fn csv_cell(value: impl AsRef<str>) -> String {
    format!("\"{}\"", value.as_ref().replace('"', "\"\""))
}

pub fn report_csv(report: &CompareReport) -> String {
    let mut out = String::from(
        "\"status\",\"relative_path\",\"size_a\",\"size_b\",\"checksum_a\",\"checksum_b\",\"xxh64_a\",\"xxh64_b\"\n",
    );
    for row in &report.rows {
        out.push_str(&format!(
            "{},{},{},{},{},{},{},{}\n",
            csv_cell(match row.status {
                FileStatus::Matching => "Matching",
                FileStatus::Changed => "Changed",
                FileStatus::OnlyInA => "OnlyInA",
                FileStatus::OnlyInB => "OnlyInB",
            }),
            csv_cell(&row.relative_path),
            csv_cell(
                row.size_a
                    .map(|value| value.to_string())
                    .unwrap_or_default()
            ),
            csv_cell(
                row.size_b
                    .map(|value| value.to_string())
                    .unwrap_or_default()
            ),
            csv_cell(row.checksum_a.clone().unwrap_or_default()),
            csv_cell(row.checksum_b.clone().unwrap_or_default()),
            csv_cell(row.xxh64_a.clone().unwrap_or_default()),
            csv_cell(row.xxh64_b.clone().unwrap_or_default())
        ));
    }
    for folder in &report.folders_only_in_a {
        out.push_str(&format!(
            "{},{},{},{},{},{},{},{}\n",
            csv_cell("FolderOnlyInA"),
            csv_cell(folder),
            csv_cell(""),
            csv_cell(""),
            csv_cell(""),
            csv_cell(""),
            csv_cell(""),
            csv_cell("")
        ));
    }
    for folder in &report.folders_only_in_b {
        out.push_str(&format!(
            "{},{},{},{},{},{},{},{}\n",
            csv_cell("FolderOnlyInB"),
            csv_cell(folder),
            csv_cell(""),
            csv_cell(""),
            csv_cell(""),
            csv_cell(""),
            csv_cell(""),
            csv_cell("")
        ));
    }
    out
}

pub fn write_text(path: &Path, contents: &str) -> Result<()> {
    let mut file =
        File::create(path).with_context(|| format!("Unable to write {}", path.display()))?;
    file.write_all(contents.as_bytes())?;
    Ok(())
}
