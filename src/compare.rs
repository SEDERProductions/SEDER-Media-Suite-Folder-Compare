// SPDX-License-Identifier: GPL-3.0-only
#![forbid(unsafe_code)]

use crate::media::MediaInfo;
use anyhow::{Context, Result};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::File;
use std::io::Read;
use std::path::Path;
use std::time::UNIX_EPOCH;
use walkdir::WalkDir;

pub const CANCELED_MESSAGE: &str = "Comparison canceled";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChecksumMethod {
    Blake3,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CompareMode {
    PathSize,
    PathSizeModified,
    PathSizeChecksum,
    MediaMetadata,
    PerceptualHash,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CompareTolerance {
    pub mtime_secs: u64,
    pub duration_ms: u64,
    pub phash_hamming: u32,
}

impl Default for CompareTolerance {
    fn default() -> Self {
        Self {
            mtime_secs: 2,
            duration_ms: 200,
            phash_hamming: 6,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProgressStage {
    ScanningA,
    ScanningB,
    Checksumming,
    Comparing,
    Transferring,
    Complete,
    Canceled,
    Failed,
}

#[derive(Debug, Clone)]
pub struct ProgressEvent {
    pub stage: ProgressStage,
    pub current: u64,
    pub total: u64,
    pub path: Option<String>,
    /// Bytes processed during a transfer or checksum operation.
    /// Populated by `transfer::copy_file` and `sync::execute_plan`; zero elsewhere.
    pub bytes_done: u64,
    /// Total bytes expected for the current operation. Zero if unknown.
    pub bytes_total: u64,
}

impl ProgressEvent {
    pub fn new(stage: ProgressStage, current: u64, total: u64, path: Option<String>) -> Self {
        Self {
            stage,
            current,
            total,
            path,
            bytes_done: 0,
            bytes_total: 0,
        }
    }

    pub fn with_bytes(mut self, done: u64, total: u64) -> Self {
        self.bytes_done = done;
        self.bytes_total = total;
        self
    }
}

#[derive(Default)]
pub struct ProgressCallbacks<'a> {
    pub progress: Option<&'a mut dyn FnMut(ProgressEvent)>,
    pub cancel: Option<&'a dyn Fn() -> bool>,
}

impl ProgressCallbacks<'_> {
    pub(crate) fn emit(&mut self, event: ProgressEvent) {
        if let Some(callback) = self.progress.as_deref_mut() {
            callback(event);
        }
    }

    pub(crate) fn check_canceled(&self) -> Result<()> {
        if self.cancel.map(|callback| callback()).unwrap_or(false) {
            anyhow::bail!(CANCELED_MESSAGE);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileChecksums {
    pub blake3: String,
}

#[derive(Debug, Clone)]
pub struct FileEntry {
    pub relative_path: String,
    pub size: u64,
    pub modified: Option<u64>,
    pub checksums: Option<FileChecksums>,
    pub is_symlink: bool,
    pub media: Option<MediaInfo>,
}

#[derive(Debug, Clone, Default)]
pub struct ScanResult {
    pub files: BTreeMap<String, FileEntry>,
    pub folders: BTreeSet<String>,
    // u64: max ~18 EB, adequate for any real storage device
    pub total_size: u64,
}

#[derive(Debug, Clone)]
pub struct ScanOptions {
    pub ignore_hidden_system: bool,
    pub ignore_patterns: Vec<String>,
    pub checksum: bool,
    pub probe_media: bool,
    pub symlink_policy: SymlinkPolicy,
}

impl Default for ScanOptions {
    fn default() -> Self {
        Self {
            ignore_hidden_system: true,
            ignore_patterns: Vec::new(),
            checksum: false,
            probe_media: false,
            symlink_policy: SymlinkPolicy::FollowInTreeOnly,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SymlinkPolicy {
    Ignore,
    FollowInTreeOnly,
    FollowAll,
    PreserveAsLink,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FileStatus {
    Matching,
    Changed,
    OnlyInA,
    OnlyInB,
    /// File present in A under one path and in B under a different path,
    /// identified as the same content via size + checksum or pHash.
    Renamed,
}

#[derive(Debug, Clone)]
pub struct ComparisonRow {
    pub relative_path: String,
    pub status: FileStatus,
    pub size_a: Option<u64>,
    pub size_b: Option<u64>,
    pub checksum_a: Option<String>,
    pub checksum_b: Option<String>,
    /// For `Renamed` rows, the original path in A. `None` otherwise.
    pub rename_from: Option<String>,
    /// For `Renamed` rows, the new path in B. `None` otherwise.
    pub rename_to: Option<String>,
}

#[derive(Debug, Clone, Default)]
pub struct CompareReport {
    pub rows: Vec<ComparisonRow>,
    pub folders_only_in_a: Vec<String>,
    pub folders_only_in_b: Vec<String>,
    pub total_files: usize,
    pub total_folders: usize,
    pub total_size: u64,
}

#[derive(Debug, Clone)]
struct IgnorePattern {
    raw: String,
    is_glob: bool,
}

#[derive(Debug, Clone, Default)]
struct IgnoreMatcher {
    patterns: Vec<IgnorePattern>,
}

impl IgnoreMatcher {
    fn new(patterns: &[String]) -> Self {
        Self {
            patterns: parse_ignore_patterns(patterns)
                .into_iter()
                .map(|raw| IgnorePattern {
                    is_glob: raw.contains('*') || raw.contains('?'),
                    raw,
                })
                .collect(),
        }
    }

    fn matches(&self, path: &Path) -> bool {
        let name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or_default();
        let normalized = path.to_string_lossy().replace('\\', "/");

        self.patterns.iter().any(|pattern| {
            if pattern.is_glob {
                wildcard_match(&pattern.raw, name) || wildcard_match(&pattern.raw, &normalized)
            } else if pattern.raw.contains('/') {
                normalized == pattern.raw || normalized.ends_with(&format!("/{}", pattern.raw))
            } else {
                name == pattern.raw
            }
        })
    }
}

pub fn parse_ignore_patterns(patterns: &[String]) -> Vec<String> {
    patterns
        .iter()
        .flat_map(|pattern| pattern.split(','))
        .map(str::trim)
        .filter(|pattern| !pattern.is_empty())
        .map(str::to_string)
        .collect()
}

/// Basic wildcard matching supporting only `*` (any sequence) and `?` (single char).
/// Does not support `**` (globstar), character classes `[...]`, or alternation `{a,b}`.
fn wildcard_match(pattern: &str, text: &str) -> bool {
    let pattern = pattern.chars().collect::<Vec<_>>();
    let text = text.chars().collect::<Vec<_>>();
    let mut previous = vec![false; text.len() + 1];
    previous[0] = true;

    for pattern_char in pattern {
        let mut next = vec![false; text.len() + 1];
        match pattern_char {
            '*' => {
                next[0] = previous[0];
                for index in 1..=text.len() {
                    next[index] = next[index - 1] || previous[index];
                }
            }
            '?' => {
                for (slot, value) in next.iter_mut().skip(1).zip(previous.iter()) {
                    *slot = *value;
                }
            }
            literal => {
                for index in 1..=text.len() {
                    next[index] = previous[index - 1] && literal == text[index - 1];
                }
            }
        }
        previous = next;
    }

    previous[text.len()]
}

fn is_hidden_or_system(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .map(|name| {
            name.starts_with('.')
                || matches!(name, "Thumbs.db" | "desktop.ini")
                || matches!(name, ".DS_Store" | ".Spotlight-V100" | ".Trashes")
        })
        .unwrap_or(false)
}

fn should_ignore(path: &Path, options: &ScanOptions, matcher: &IgnoreMatcher) -> bool {
    (options.ignore_hidden_system && is_hidden_or_system(path)) || matcher.matches(path)
}

fn relative(root: &Path, path: &Path) -> Result<String> {
    let stripped = path.strip_prefix(root)?;
    Ok(stripped.to_string_lossy().replace('\\', "/"))
}

fn should_emit_progress(current: u64, total: u64) -> bool {
    if current <= 5 {
        return true;
    }
    if total > 0 {
        let step = (total / 100).max(1);
        current.is_multiple_of(step)
    } else {
        current.is_multiple_of(10)
    }
}

fn emit_progress(
    callbacks: &mut ProgressCallbacks<'_>,
    stage: ProgressStage,
    current: u64,
    total: u64,
    path: Option<String>,
) {
    if should_emit_progress(current, total)
        || matches!(
            stage,
            ProgressStage::Complete | ProgressStage::Canceled | ProgressStage::Failed
        )
    {
        callbacks.emit(ProgressEvent::new(stage, current, total, path));
    }
}

pub fn checksum_file(path: &Path, method: ChecksumMethod) -> Result<String> {
    match method {
        ChecksumMethod::Blake3 => Ok(checksum_file_set(path)?.blake3),
    }
}

pub fn checksum_file_set(path: &Path) -> Result<FileChecksums> {
    let mut callbacks = ProgressCallbacks::default();
    checksum_file_set_with_progress(path, ProgressStage::Checksumming, 0, &mut callbacks)
}

fn checksum_file_set_with_progress(
    path: &Path,
    stage: ProgressStage,
    current: u64,
    callbacks: &mut ProgressCallbacks<'_>,
) -> Result<FileChecksums> {
    callbacks.check_canceled()?;
    emit_progress(
        callbacks,
        stage,
        current,
        0,
        Some(path.to_string_lossy().to_string()),
    );

    let mut hasher = blake3::Hasher::new();
    let mut file =
        File::open(path).with_context(|| format!("Unable to read {}", path.display()))?;
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        callbacks.check_canceled()?;
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Ok(FileChecksums {
        blake3: hasher.finalize().to_hex().to_string(),
    })
}

pub fn scan_folder(root: &Path, options: &ScanOptions) -> Result<ScanResult> {
    let mut callbacks = ProgressCallbacks::default();
    scan_folder_with_progress(root, options, ProgressStage::ScanningA, &mut callbacks)
}

pub fn scan_folder_with_progress(
    root: &Path,
    options: &ScanOptions,
    stage: ProgressStage,
    callbacks: &mut ProgressCallbacks<'_>,
) -> Result<ScanResult> {
    if !root.is_dir() {
        anyhow::bail!("Folder does not exist: {}", root.display());
    }

    let matcher = IgnoreMatcher::new(&options.ignore_patterns);
    let canonical_root = root
        .canonicalize()
        .with_context(|| format!("Unable to canonicalize root {}", root.display()))?;
    let mut result = ScanResult::default();
    let mut visited = 0_u64;

    emit_progress(
        callbacks,
        stage,
        visited,
        0,
        Some(root.display().to_string()),
    );

    for entry in WalkDir::new(root)
        .into_iter()
        .filter_entry(|entry| entry.depth() == 0 || !should_ignore(entry.path(), options, &matcher))
    {
        callbacks.check_canceled()?;
        let entry = entry?;
        if entry.depth() == 0 {
            continue;
        }

        visited += 1;
        let rel = relative(root, entry.path())?;
        emit_progress(callbacks, stage, visited, 0, Some(rel.clone()));

        if entry.file_type().is_dir() {
            result.folders.insert(rel);
            continue;
        }

        if entry.file_type().is_file() || entry.file_type().is_symlink() {
            let is_symlink = entry.file_type().is_symlink();
            let metadata = if is_symlink {
                match options.symlink_policy {
                    SymlinkPolicy::Ignore => continue,
                    SymlinkPolicy::PreserveAsLink => std::fs::symlink_metadata(entry.path())
                        .map_err(|e| {
                            anyhow::Error::from(e)
                                .context(format!("Unable to stat {}", entry.path().display()))
                        })?,
                    SymlinkPolicy::FollowAll | SymlinkPolicy::FollowInTreeOnly => {
                        let canonical_target = match entry.path().canonicalize() {
                            Ok(path) => path,
                            Err(_) => continue, // broken symlink
                        };
                        if options.symlink_policy == SymlinkPolicy::FollowInTreeOnly
                            && !canonical_target.starts_with(&canonical_root)
                        {
                            continue;
                        }
                        std::fs::metadata(&canonical_target).with_context(|| {
                            format!(
                                "Unable to stat symlink target {}",
                                canonical_target.display()
                            )
                        })?
                    }
                }
            } else {
                entry.metadata().map_err(|e| {
                    anyhow::Error::from(e)
                        .context(format!("Unable to stat {}", entry.path().display()))
                })?
            };
            // A symlink-to-directory resolves to a directory here; record it as
            // a folder rather than inserting a phantom file row.
            if metadata.is_dir() {
                result.folders.insert(rel);
                continue;
            }
            if !(metadata.is_file()
                || (is_symlink && options.symlink_policy == SymlinkPolicy::PreserveAsLink))
            {
                continue;
            }
            let modified = metadata
                .modified()
                .ok()
                .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
                .map(|duration| duration.as_secs());
            let checksums = if options.checksum {
                Some(checksum_file_set_with_progress(
                    entry.path(),
                    ProgressStage::Checksumming,
                    visited,
                    callbacks,
                )?)
            } else {
                None
            };
            let media = if options.probe_media {
                crate::media::probe(entry.path()).ok().flatten()
            } else {
                None
            };
            result.total_size = result.total_size.saturating_add(metadata.len());
            result.files.insert(
                rel.clone(),
                FileEntry {
                    relative_path: rel,
                    size: metadata.len(),
                    modified,
                    checksums,
                    is_symlink,
                    media,
                },
            );
        }
    }

    Ok(result)
}

fn modified_within_tolerance(a: Option<u64>, b: Option<u64>, tolerance_secs: u64) -> bool {
    match (a, b) {
        (Some(av), Some(bv)) => av.abs_diff(bv) <= tolerance_secs,
        (None, None) => true,
        _ => false,
    }
}

fn duration_within_tolerance(a: Option<u32>, b: Option<u32>, tolerance_ms: u64) -> bool {
    match (a, b) {
        (Some(av), Some(bv)) => (av as u64).abs_diff(bv as u64) <= tolerance_ms,
        (None, None) => true,
        _ => false,
    }
}

fn files_match(a: &FileEntry, b: &FileEntry, mode: CompareMode, tol: CompareTolerance) -> bool {
    match mode {
        CompareMode::PathSize => a.size == b.size,
        CompareMode::PathSizeModified => {
            a.size == b.size && modified_within_tolerance(a.modified, b.modified, tol.mtime_secs)
        }
        CompareMode::PathSizeChecksum => {
            a.size == b.size
                && a.checksums.as_ref().map(|checksums| &checksums.blake3)
                    == b.checksums.as_ref().map(|checksums| &checksums.blake3)
        }
        CompareMode::MediaMetadata => match (&a.media, &b.media) {
            (Some(am), Some(bm)) => {
                am.kind == bm.kind
                    && am.width == bm.width
                    && am.height == bm.height
                    && duration_within_tolerance(am.duration_ms, bm.duration_ms, tol.duration_ms)
                    && am.sample_rate == bm.sample_rate
            }
            (None, None) => a.size == b.size,
            _ => false,
        },
        CompareMode::PerceptualHash => match (a.media.as_ref(), b.media.as_ref()) {
            (Some(am), Some(bm)) => match (am.phash, bm.phash) {
                (Some(ah), Some(bh)) => {
                    let hamming = (ah ^ bh).count_ones();
                    hamming <= tol.phash_hamming
                }
                _ => {
                    a.size == b.size
                        && a.checksums.as_ref().map(|c| &c.blake3)
                            == b.checksums.as_ref().map(|c| &c.blake3)
                }
            },
            _ => {
                a.size == b.size
                    && a.checksums.as_ref().map(|c| &c.blake3)
                        == b.checksums.as_ref().map(|c| &c.blake3)
            }
        },
    }
}

pub fn compare_scans(a: &ScanResult, b: &ScanResult, mode: CompareMode) -> CompareReport {
    let mut callbacks = ProgressCallbacks::default();
    compare_scans_with_progress(a, b, mode, CompareTolerance::default(), &mut callbacks)
        .expect("comparison without cancellation should not fail")
}

pub fn compare_scans_with_progress(
    a: &ScanResult,
    b: &ScanResult,
    mode: CompareMode,
    tolerance: CompareTolerance,
    callbacks: &mut ProgressCallbacks<'_>,
) -> Result<CompareReport> {
    let mut keys = BTreeSet::new();
    keys.extend(a.files.keys().cloned());
    keys.extend(b.files.keys().cloned());
    let total = keys.len() as u64;

    let mut rows = Vec::with_capacity(keys.len());
    let total_keys = keys.len();
    for (index, key) in keys.into_iter().enumerate() {
        callbacks.check_canceled()?;
        let current = index as u64 + 1;
        emit_progress(
            callbacks,
            ProgressStage::Comparing,
            current,
            total,
            Some(key.clone()),
        );

        let left = a.files.get(&key);
        let right = b.files.get(&key);
        let status = match (left, right) {
            (Some(l), Some(r)) if files_match(l, r, mode, tolerance) => FileStatus::Matching,
            (Some(_), Some(_)) => FileStatus::Changed,
            (Some(_), None) => FileStatus::OnlyInA,
            (None, Some(_)) => FileStatus::OnlyInB,
            (None, None) => unreachable!(),
        };
        rows.push(ComparisonRow {
            relative_path: key,
            status,
            size_a: left.map(|entry| entry.size),
            size_b: right.map(|entry| entry.size),
            checksum_a: left.and_then(|entry| {
                entry
                    .checksums
                    .as_ref()
                    .map(|checksums| checksums.blake3.clone())
            }),
            checksum_b: right.and_then(|entry| {
                entry
                    .checksums
                    .as_ref()
                    .map(|checksums| checksums.blake3.clone())
            }),
            rename_from: None,
            rename_to: None,
        });
    }

    Ok(CompareReport {
        rows,
        folders_only_in_a: a.folders.difference(&b.folders).cloned().collect(),
        folders_only_in_b: b.folders.difference(&a.folders).cloned().collect(),
        total_files: total_keys,
        total_folders: a.folders.union(&b.folders).count(),
        // Combined size of both sides (a file present on both sides counts twice)
        total_size: a.total_size.saturating_add(b.total_size),
    })
}

/// Run rename detection over a report's `OnlyInA`/`OnlyInB` rows.
///
/// A pair of (OnlyInA, OnlyInB) rows is reclassified as `Renamed` when they share size
/// and (in order of preference) the same BLAKE3 checksum, or the same pHash within the
/// configured Hamming tolerance.
pub fn detect_renames(
    report: &mut CompareReport,
    a: &ScanResult,
    b: &ScanResult,
    tol: CompareTolerance,
) {
    let mut a_only: Vec<usize> = Vec::new();
    let mut b_only: Vec<usize> = Vec::new();
    for (idx, row) in report.rows.iter().enumerate() {
        match row.status {
            FileStatus::OnlyInA => a_only.push(idx),
            FileStatus::OnlyInB => b_only.push(idx),
            _ => {}
        }
    }
    let mut consumed_b: BTreeSet<usize> = BTreeSet::new();
    for ai in a_only {
        let a_row = &report.rows[ai];
        let a_entry = match a.files.get(&a_row.relative_path) {
            Some(e) => e,
            None => continue,
        };
        let mut matched: Option<usize> = None;
        for bi in &b_only {
            if consumed_b.contains(bi) {
                continue;
            }
            let b_row = &report.rows[*bi];
            let b_entry = match b.files.get(&b_row.relative_path) {
                Some(e) => e,
                None => continue,
            };
            if a_entry.size != b_entry.size {
                continue;
            }
            let checksum_match = match (a_entry.checksums.as_ref(), b_entry.checksums.as_ref()) {
                (Some(x), Some(y)) => x.blake3 == y.blake3,
                _ => false,
            };
            let phash_match = match (
                a_entry.media.as_ref().and_then(|m| m.phash),
                b_entry.media.as_ref().and_then(|m| m.phash),
            ) {
                (Some(x), Some(y)) => (x ^ y).count_ones() <= tol.phash_hamming,
                _ => false,
            };
            if checksum_match || phash_match {
                matched = Some(*bi);
                break;
            }
        }
        if let Some(bi) = matched {
            consumed_b.insert(bi);
            let from = report.rows[ai].relative_path.clone();
            let to = report.rows[bi].relative_path.clone();
            report.rows[ai].status = FileStatus::Renamed;
            report.rows[ai].rename_from = Some(from.clone());
            report.rows[ai].rename_to = Some(to.clone());
            report.rows[ai].size_b = report.rows[bi].size_b;
            report.rows[ai].checksum_b = report.rows[bi].checksum_b.clone();
            // Mark the partner row for removal by setting its status to a sentinel and dropping later.
            report.rows[bi].status = FileStatus::Renamed;
            report.rows[bi].rename_from = Some(from);
            report.rows[bi].rename_to = Some(to);
        }
    }
    // Drop the duplicate (b-side) Renamed rows: we keep the first occurrence per (from,to) pair.
    let mut seen: BTreeSet<(String, String)> = BTreeSet::new();
    report.rows.retain(|row| {
        if row.status == FileStatus::Renamed {
            if let (Some(f), Some(t)) = (row.rename_from.as_ref(), row.rename_to.as_ref()) {
                let key = (f.clone(), t.clone());
                if seen.contains(&key) {
                    return false;
                }
                seen.insert(key);
            }
        }
        true
    });
}

pub fn compare_folders(
    a: &Path,
    b: &Path,
    mode: CompareMode,
    ignore_hidden_system: bool,
    ignore_patterns: Vec<String>,
) -> Result<CompareReport> {
    let mut callbacks = ProgressCallbacks::default();
    compare_folders_with_progress(
        a,
        b,
        mode,
        ignore_hidden_system,
        ignore_patterns,
        CompareTolerance::default(),
        false,
        false,
        &mut callbacks,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn compare_folders_with_progress(
    a: &Path,
    b: &Path,
    mode: CompareMode,
    ignore_hidden_system: bool,
    ignore_patterns: Vec<String>,
    tolerance: CompareTolerance,
    follow_symlinks: bool,
    detect_renames_pass: bool,
    callbacks: &mut ProgressCallbacks<'_>,
) -> Result<CompareReport> {
    callbacks.check_canceled()?;
    let checksum = matches!(
        mode,
        CompareMode::PathSizeChecksum | CompareMode::PerceptualHash
    );
    let probe_media = matches!(
        mode,
        CompareMode::MediaMetadata | CompareMode::PerceptualHash
    );
    let symlink_policy = if follow_symlinks {
        SymlinkPolicy::FollowInTreeOnly
    } else {
        SymlinkPolicy::Ignore
    };
    let options = ScanOptions {
        ignore_hidden_system,
        ignore_patterns,
        checksum,
        probe_media,
        symlink_policy,
    };

    let left = scan_folder_with_progress(a, &options, ProgressStage::ScanningA, callbacks)?;
    callbacks.check_canceled()?;
    let right = scan_folder_with_progress(b, &options, ProgressStage::ScanningB, callbacks)?;
    callbacks.check_canceled()?;
    let mut report = compare_scans_with_progress(&left, &right, mode, tolerance, callbacks)?;
    if detect_renames_pass {
        detect_renames(&mut report, &left, &right, tolerance);
    }
    emit_progress(
        callbacks,
        ProgressStage::Complete,
        report.rows.len() as u64,
        report.rows.len() as u64,
        None,
    );
    Ok(report)
}

pub fn file_count_folder_count_size(scan: &ScanResult) -> (usize, usize, u64) {
    (scan.files.len(), scan.folders.len(), scan.total_size)
}

pub fn path_buf_string(path: &Path) -> String {
    path.to_string_lossy().to_string()
}
