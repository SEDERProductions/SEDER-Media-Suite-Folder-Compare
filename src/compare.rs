// SPDX-License-Identifier: GPL-3.0-only

use anyhow::{Context, Result};
use std::collections::{BTreeMap, BTreeSet};
use std::fs::File;
use std::hash::Hasher;
use std::io::Read;
use std::path::Path;
use std::time::UNIX_EPOCH;
use twox_hash::XxHash64;
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
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProgressStage {
    ScanningA,
    ScanningB,
    Checksumming,
    Comparing,
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
    pub xxh64: String,
}

#[derive(Debug, Clone)]
pub struct FileEntry {
    pub relative_path: String,
    pub size: u64,
    pub modified: Option<u64>,
    pub checksums: Option<FileChecksums>,
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
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FileStatus {
    Matching,
    Changed,
    OnlyInA,
    OnlyInB,
}

#[derive(Debug, Clone)]
pub struct ComparisonRow {
    pub relative_path: String,
    pub status: FileStatus,
    pub size_a: Option<u64>,
    pub size_b: Option<u64>,
    pub checksum_a: Option<String>,
    pub checksum_b: Option<String>,
    pub xxh64_a: Option<String>,
    pub xxh64_b: Option<String>,
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
        current.is_multiple_of(50)
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
        callbacks.emit(ProgressEvent {
            stage,
            current,
            total,
            path,
        });
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

    let mut blake3_hasher = blake3::Hasher::new();
    let mut xxh64_hasher = XxHash64::with_seed(0);
    let mut file =
        File::open(path).with_context(|| format!("Unable to read {}", path.display()))?;
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        callbacks.check_canceled()?;
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        let chunk = &buffer[..read];
        blake3_hasher.update(chunk);
        xxh64_hasher.write(chunk);
    }
    Ok(FileChecksums {
        blake3: blake3_hasher.finalize().to_hex().to_string(),
        xxh64: format!("{:016x}", xxh64_hasher.finish()),
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
        if entry.depth() == 0 || should_ignore(entry.path(), options, &matcher) {
            continue;
        }

        visited += 1;
        let rel = relative(root, entry.path())?;
        emit_progress(callbacks, stage, visited, 0, Some(rel.clone()));

        if entry.file_type().is_dir() {
            result.folders.insert(rel);
            continue;
        }

        // Treat regular files and symlinks (resolved via std::fs::metadata below)
        // as files. WalkDir defaults to follow_links(false), so symlinks otherwise
        // get silently dropped here, which masks real divergences when one side
        // resolves a symlink into a real copy of the file.
        if entry.file_type().is_file() || entry.file_type().is_symlink() {
            let metadata = match std::fs::metadata(entry.path()) {
                Ok(m) => m,
                Err(_) if entry.file_type().is_symlink() => {
                    // Broken symlink or symlink target is unreachable; skip it
                    // rather than aborting the whole scan.
                    continue;
                }
                Err(e) => {
                    return Err(anyhow::Error::from(e)
                        .context(format!("Unable to stat {}", entry.path().display())));
                }
            };
            // A symlink-to-directory resolves to a directory here; record it as
            // a folder rather than inserting a phantom file row.
            if metadata.is_dir() {
                result.folders.insert(rel);
                continue;
            }
            if !metadata.is_file() {
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
            result.total_size += metadata.len();
            result.files.insert(
                rel.clone(),
                FileEntry {
                    relative_path: rel,
                    size: metadata.len(),
                    modified,
                    checksums,
                },
            );
        }
    }

    Ok(result)
}

fn files_match(a: &FileEntry, b: &FileEntry, mode: CompareMode) -> bool {
    match mode {
        CompareMode::PathSize => a.size == b.size,
        CompareMode::PathSizeModified => a.size == b.size && a.modified == b.modified,
        CompareMode::PathSizeChecksum => {
            a.size == b.size
                && a.checksums.as_ref().map(|checksums| &checksums.blake3)
                    == b.checksums.as_ref().map(|checksums| &checksums.blake3)
        }
    }
}

pub fn compare_scans(a: &ScanResult, b: &ScanResult, mode: CompareMode) -> CompareReport {
    let mut callbacks = ProgressCallbacks::default();
    compare_scans_with_progress(a, b, mode, &mut callbacks)
        .expect("comparison without cancellation should not fail")
}

pub fn compare_scans_with_progress(
    a: &ScanResult,
    b: &ScanResult,
    mode: CompareMode,
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
            (Some(l), Some(r)) if files_match(l, r, mode) => FileStatus::Matching,
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
            xxh64_a: left.and_then(|entry| {
                entry
                    .checksums
                    .as_ref()
                    .map(|checksums| checksums.xxh64.clone())
            }),
            xxh64_b: right.and_then(|entry| {
                entry
                    .checksums
                    .as_ref()
                    .map(|checksums| checksums.xxh64.clone())
            }),
        });
    }

    Ok(CompareReport {
        rows,
        folders_only_in_a: a.folders.difference(&b.folders).cloned().collect(),
        folders_only_in_b: b.folders.difference(&a.folders).cloned().collect(),
        total_files: total_keys,
        total_folders: a.folders.union(&b.folders).count(),
        // Combined size of both sides (a file present on both sides counts twice)
        total_size: a.total_size + b.total_size,
    })
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
        &mut callbacks,
    )
}

pub fn compare_folders_with_progress(
    a: &Path,
    b: &Path,
    mode: CompareMode,
    ignore_hidden_system: bool,
    ignore_patterns: Vec<String>,
    callbacks: &mut ProgressCallbacks<'_>,
) -> Result<CompareReport> {
    callbacks.check_canceled()?;
    let checksum = mode == CompareMode::PathSizeChecksum;
    let options = ScanOptions {
        ignore_hidden_system,
        ignore_patterns: parse_ignore_patterns(&ignore_patterns),
        checksum,
    };

    let left = scan_folder_with_progress(a, &options, ProgressStage::ScanningA, callbacks)?;
    callbacks.check_canceled()?;
    let right = scan_folder_with_progress(b, &options, ProgressStage::ScanningB, callbacks)?;
    callbacks.check_canceled()?;
    let report = compare_scans_with_progress(&left, &right, mode, callbacks)?;
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
