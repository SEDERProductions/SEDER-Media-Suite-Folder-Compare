// SPDX-License-Identifier: GPL-3.0-only
#![forbid(unsafe_code)]

//! Sync planning and execution.
//!
//! A `SyncPlan` is a deterministic, ordered list of actions derived from a
//! `CompareReport` plus a chosen `SyncMode`. The plan can be inspected (dry-run)
//! or executed via `execute_plan`, which reuses the transfer primitives in
//! `crate::transfer`.

use crate::compare::{
    CompareReport, ComparisonRow, FileStatus, ProgressCallbacks, ProgressEvent, ProgressStage,
};
use crate::transfer;
use anyhow::{Context, Result};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncMode {
    MirrorAToB,
    MirrorBToA,
    TwoWayNewerWins,
    TwoWayManual,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConflictStrategy {
    NewerWins,
    LargerWins,
    AskUser,
    Skip,
}

#[derive(Debug, Clone)]
pub struct SyncOptions {
    pub propagate_deletes: bool,
    pub dry_run: bool,
    pub conflict_strategy: ConflictStrategy,
}

impl Default for SyncOptions {
    fn default() -> Self {
        Self {
            propagate_deletes: true,
            dry_run: false,
            conflict_strategy: ConflictStrategy::NewerWins,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SyncActionKind {
    Copy,
    Delete,
    Rename,
    Skip,
}

#[derive(Debug, Clone)]
pub struct SyncAction {
    pub kind: SyncActionKind,
    pub source: PathBuf,
    pub dest: PathBuf,
    pub relative_path: String,
    pub reason: String,
}

#[derive(Debug, Clone, Default)]
pub struct SyncPlan {
    pub actions: Vec<SyncAction>,
}

impl SyncPlan {
    pub fn len(&self) -> usize {
        self.actions.len()
    }
    pub fn is_empty(&self) -> bool {
        self.actions.is_empty()
    }
}

/// Build a sync plan from a comparison report.
///
/// `folder_a` and `folder_b` are the root paths the report was generated from;
/// the plan's actions reference absolute paths derived from those roots.
pub fn build_plan(
    report: &CompareReport,
    folder_a: &Path,
    folder_b: &Path,
    mode: SyncMode,
    options: &SyncOptions,
) -> SyncPlan {
    let mut plan = SyncPlan::default();
    for row in &report.rows {
        if let Some(action) = plan_row(row, folder_a, folder_b, mode, options) {
            plan.actions.push(action);
        }
    }
    plan
}

fn plan_row(
    row: &ComparisonRow,
    a: &Path,
    b: &Path,
    mode: SyncMode,
    options: &SyncOptions,
) -> Option<SyncAction> {
    let rel = &row.relative_path;
    let path_a = a.join(rel);
    let path_b = b.join(rel);

    match (mode, &row.status) {
        // -------- mirror A → B --------
        (SyncMode::MirrorAToB, FileStatus::OnlyInA)
        | (SyncMode::MirrorAToB, FileStatus::Changed) => Some(SyncAction {
            kind: SyncActionKind::Copy,
            source: path_a,
            dest: path_b,
            relative_path: rel.clone(),
            reason: "mirror A→B".to_string(),
        }),
        (SyncMode::MirrorAToB, FileStatus::OnlyInB) if options.propagate_deletes => {
            Some(SyncAction {
                kind: SyncActionKind::Delete,
                source: path_b.clone(),
                dest: path_b,
                relative_path: rel.clone(),
                reason: "delete extraneous in B".to_string(),
            })
        }

        // -------- mirror B → A --------
        (SyncMode::MirrorBToA, FileStatus::OnlyInB)
        | (SyncMode::MirrorBToA, FileStatus::Changed) => Some(SyncAction {
            kind: SyncActionKind::Copy,
            source: path_b,
            dest: path_a,
            relative_path: rel.clone(),
            reason: "mirror B→A".to_string(),
        }),
        (SyncMode::MirrorBToA, FileStatus::OnlyInA) if options.propagate_deletes => {
            Some(SyncAction {
                kind: SyncActionKind::Delete,
                source: path_a.clone(),
                dest: path_a,
                relative_path: rel.clone(),
                reason: "delete extraneous in A".to_string(),
            })
        }

        // -------- two-way newer wins --------
        (SyncMode::TwoWayNewerWins, FileStatus::OnlyInA) => Some(SyncAction {
            kind: SyncActionKind::Copy,
            source: path_a,
            dest: path_b,
            relative_path: rel.clone(),
            reason: "two-way: missing in B".to_string(),
        }),
        (SyncMode::TwoWayNewerWins, FileStatus::OnlyInB) => Some(SyncAction {
            kind: SyncActionKind::Copy,
            source: path_b,
            dest: path_a,
            relative_path: rel.clone(),
            reason: "two-way: missing in A".to_string(),
        }),
        (SyncMode::TwoWayNewerWins, FileStatus::Changed) => {
            // Caller did not provide mtime here; resolve by size as a fallback
            // when strategy is LargerWins, otherwise default to A→B.
            let direction = match options.conflict_strategy {
                ConflictStrategy::LargerWins => row.size_a.unwrap_or(0) >= row.size_b.unwrap_or(0),
                ConflictStrategy::Skip | ConflictStrategy::AskUser => {
                    return Some(SyncAction {
                        kind: SyncActionKind::Skip,
                        source: path_a,
                        dest: path_b,
                        relative_path: rel.clone(),
                        reason: "two-way conflict requires user decision".to_string(),
                    })
                }
                ConflictStrategy::NewerWins => true,
            };
            if direction {
                Some(SyncAction {
                    kind: SyncActionKind::Copy,
                    source: path_a,
                    dest: path_b,
                    relative_path: rel.clone(),
                    reason: "two-way: A wins".to_string(),
                })
            } else {
                Some(SyncAction {
                    kind: SyncActionKind::Copy,
                    source: path_b,
                    dest: path_a,
                    relative_path: rel.clone(),
                    reason: "two-way: B wins".to_string(),
                })
            }
        }

        // -------- rename --------
        (_, FileStatus::Renamed) => {
            let from = row.rename_from.clone().unwrap_or_else(|| rel.clone());
            let to = row.rename_to.clone().unwrap_or_else(|| rel.clone());
            let source = match mode {
                SyncMode::MirrorBToA => b.join(&to),
                _ => a.join(&from),
            };
            let dest = match mode {
                SyncMode::MirrorBToA => a.join(&from),
                _ => b.join(&to),
            };
            Some(SyncAction {
                kind: SyncActionKind::Rename,
                source,
                dest,
                relative_path: rel.clone(),
                reason: format!("renamed: {from} → {to}"),
            })
        }

        // -------- manual --------
        (SyncMode::TwoWayManual, _) => None,

        _ => None,
    }
}

/// Execute every action in the plan. Honors `options.dry_run`: when true,
/// emits progress events but never touches disk.
pub fn execute_plan(
    plan: &SyncPlan,
    options: &SyncOptions,
    callbacks: &mut ProgressCallbacks<'_>,
) -> Result<()> {
    let total = plan.actions.len() as u64;
    for (idx, action) in plan.actions.iter().enumerate() {
        callbacks.check_canceled()?;
        let current = idx as u64 + 1;
        callbacks.emit(ProgressEvent::new(
            ProgressStage::Transferring,
            current,
            total,
            Some(action.relative_path.clone()),
        ));

        if options.dry_run {
            continue;
        }
        match action.kind {
            SyncActionKind::Copy => transfer::copy_file(&action.source, &action.dest, callbacks)
                .with_context(|| {
                    format!(
                        "copy failed: {} → {}",
                        action.source.display(),
                        action.dest.display()
                    )
                })?,
            SyncActionKind::Delete => {
                let p = &action.source;
                if p.is_dir() {
                    transfer::remove_folder(p)?;
                } else if p.is_file() || p.is_symlink() {
                    transfer::remove_file(p)?;
                }
            }
            SyncActionKind::Rename => {
                if let Some(parent) = action.dest.parent() {
                    std::fs::create_dir_all(parent).ok();
                }
                std::fs::rename(&action.source, &action.dest).with_context(|| {
                    format!(
                        "rename failed: {} → {}",
                        action.source.display(),
                        action.dest.display()
                    )
                })?;
            }
            SyncActionKind::Skip => {}
        }
    }
    callbacks.emit(ProgressEvent::new(
        ProgressStage::Complete,
        total,
        total,
        None,
    ));
    Ok(())
}
