// SPDX-License-Identifier: GPL-3.0-only

use crate::compare::{ProgressCallbacks, ProgressEvent, ProgressStage};
use anyhow::{Context, Result};
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};
use walkdir::WalkDir;

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct FileMetadata {
    pub size: u64,
    pub modified: Option<u64>,
}

#[allow(dead_code)]
pub fn get_file_metadata(path: &Path) -> Result<FileMetadata> {
    let metadata = fs::metadata(path)?;
    let modified = metadata
        .modified()
        .ok()
        .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_secs());
    Ok(FileMetadata {
        size: metadata.len(),
        modified,
    })
}

pub fn copy_file(source: &Path, dest: &Path, callbacks: &mut ProgressCallbacks<'_>) -> Result<()> {
    callbacks.check_canceled()?;

    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("Failed to create directory {}", parent.display()))?;
    }

    let total = fs::metadata(source)
        .with_context(|| format!("Failed to stat source {}", source.display()))?
        .len();
    let mut source_file = fs::File::open(source)
        .with_context(|| format!("Failed to open source {}", source.display()))?;

    let dest_dir = dest.parent().unwrap_or_else(|| Path::new("."));
    let dest_name = dest
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("dest");
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let temp_path = dest_dir.join(format!(".{dest_name}.sfc.tmp.{}.{}", std::process::id(), unique));

    let mut dest_file = fs::File::create(&temp_path)
        .with_context(|| format!("Failed to create temporary destination {}", temp_path.display()))?;

    let result: Result<()> = (|| {
        let mut buffer = [0_u8; 64 * 1024];
        let mut transferred = 0_u64;

        loop {
            callbacks.check_canceled()?;
            let read = source_file
                .read(&mut buffer)
                .with_context(|| format!("Failed to read source {}", source.display()))?;
            if read == 0 {
                break;
            }
            dest_file
                .write_all(&buffer[..read])
                .with_context(|| format!("Failed to write temporary destination {}", temp_path.display()))?;
            transferred = transferred.saturating_add(read as u64);
            callbacks.emit(
                ProgressEvent::new(
                    ProgressStage::Transferring,
                    transferred,
                    total,
                    Some(dest_name.to_string()),
                )
                .with_bytes(transferred, total),
            );
        }

        dest_file.flush()?;
        dest_file.sync_all()?;
        Ok(())
    })();

    if let Err(err) = result {
        let _ = fs::remove_file(&temp_path);
        return Err(err);
    }

    fs::rename(&temp_path, dest).with_context(|| {
        format!(
            "Failed to atomically replace destination {} with {}",
            dest.display(),
            temp_path.display()
        )
    })?;

    Ok(())
}

pub fn copy_folder(
    source: &Path,
    dest: &Path,
    callbacks: &mut ProgressCallbacks<'_>,
) -> Result<()> {
    callbacks.check_canceled()?;

    if !source.is_dir() {
        anyhow::bail!("Source is not a directory: {}", source.display());
    }

    let entries: Vec<_> = WalkDir::new(source)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.depth() > 0)
        .collect();

    let source_root = source
        .canonicalize()
        .with_context(|| format!("Failed to resolve source root {}", source.display()))?;

    let total = entries.len() as u64;

    for (index, entry) in entries.iter().enumerate() {
        callbacks.check_canceled()?;

        let rel = entry.path().strip_prefix(source).with_context(|| {
            format!("Failed to compute relative path from {}", source.display())
        })?;
        let dest_path = dest.join(rel);
        let current = index as u64 + 1;

        callbacks.emit(ProgressEvent::new(
            ProgressStage::Transferring,
            current,
            total,
            Some(rel.to_string_lossy().to_string()),
        ));

        if entry.file_type().is_dir() {
            fs::create_dir_all(&dest_path)
                .with_context(|| format!("Failed to create directory {}", dest_path.display()))?;
        } else if entry.file_type().is_file() || entry.file_type().is_symlink() {
            if let Some(parent) = dest_path.parent() {
                fs::create_dir_all(parent)
                    .with_context(|| format!("Failed to create directory {}", parent.display()))?;
            }

            let source_to_copy: PathBuf = if entry.file_type().is_symlink() {
                let link_target = fs::read_link(entry.path()).with_context(|| {
                    format!(
                        "Failed to read symlink at '{}' while copying folder",
                        rel.display()
                    )
                })?;
                let resolved_target = if link_target.is_absolute() {
                    link_target
                } else {
                    entry.path().parent().unwrap_or(source).join(link_target)
                };
                let canonical_target = resolved_target.canonicalize().with_context(|| {
                    format!(
                        "Disallowed symlink '{}' because its target is missing or broken.                          Replace it with a valid file under the source root or remove the link.",
                        rel.display()
                    )
                })?;

                if !canonical_target.starts_with(&source_root) {
                    anyhow::bail!(
                        "Disallowed symlink '{}' because its target resolves outside the source root.                          Update the symlink target to a file under '{}' or remove the link.",
                        rel.display(),
                        source.display()
                    );
                }

                if !canonical_target.is_file() {
                    anyhow::bail!(
                        "Disallowed symlink '{}' because it does not resolve to a regular file.                          Update the link to point to a file under '{}' or remove the link.",
                        rel.display(),
                        source.display()
                    );
                }

                canonical_target
            } else {
                entry.path().to_path_buf()
            };

            fs::copy(&source_to_copy, &dest_path).with_context(|| {
                format!(
                    "Failed to copy {} to {}",
                    source_to_copy.display(),
                    dest_path.display()
                )
            })?;
        }
    }

    Ok(())
}

pub fn remove_file(path: &Path) -> Result<()> {
    fs::remove_file(path).with_context(|| format!("Failed to remove file {}", path.display()))
}

pub fn remove_folder(path: &Path) -> Result<()> {
    fs::remove_dir_all(path)
        .with_context(|| format!("Failed to remove directory {}", path.display()))
}

#[allow(dead_code)]
pub fn verify_file(path: &Path, expected_size: u64) -> Result<bool> {
    match fs::metadata(path) {
        Ok(metadata) => Ok(metadata.len() == expected_size),
        Err(_) => Ok(false),
    }
}
