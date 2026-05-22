// SPDX-License-Identifier: GPL-3.0-only
#![forbid(unsafe_code)]

//! `sfc` — command-line interface to the SEDER folder-compare library.
//!
//! Exit codes:
//!   0 — comparison complete with no differences / sync completed cleanly
//!   1 — differences found (compare subcommand)
//!   2 — error
//! 130 — canceled (reserved; the CLI never traps SIGINT today)

use clap::{Parser, Subcommand, ValueEnum};
use seder_folder_compare::{
    build_sync_plan, checksum_file, compare_folders_with_progress, execute_sync_plan, probe_media,
    report_csv, report_txt, write_text, ChecksumMethod, CompareMode, CompareTolerance,
    ConflictStrategy, FileStatus, ProgressCallbacks, SyncMode, SyncOptions,
};
use std::path::PathBuf;
use std::process::ExitCode;

#[derive(Parser)]
#[command(name = "sfc", version, about = "SEDER folder compare — CLI")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Compare two folders and print or write a report.
    Compare {
        folder_a: PathBuf,
        folder_b: PathBuf,
        #[arg(long, value_enum, default_value_t = ModeArg::PathSize)]
        mode: ModeArg,
        #[arg(long)]
        ignore_hidden: bool,
        #[arg(long = "ignore", value_name = "PATTERN")]
        ignore: Vec<String>,
        #[arg(long, value_enum, default_value_t = OutputFormat::Text)]
        format: OutputFormat,
        #[arg(long)]
        out: Option<PathBuf>,
        #[arg(long)]
        follow_symlinks: bool,
        #[arg(long)]
        detect_renames: bool,
        #[arg(long, default_value_t = 2)]
        tolerance_mtime: u64,
        #[arg(long, default_value_t = 200)]
        tolerance_duration_ms: u64,
        #[arg(long, default_value_t = 6)]
        tolerance_phash: u32,
    },
    /// Plan and optionally execute a sync between two folders.
    Sync {
        folder_a: PathBuf,
        folder_b: PathBuf,
        #[arg(long, value_enum)]
        mode: SyncModeArg,
        #[arg(long)]
        delete: bool,
        #[arg(long)]
        dry_run: bool,
        #[arg(long, value_enum, default_value_t = ConflictArg::NewerWins)]
        conflict: ConflictArg,
    },
    /// Compute a hash for a single file.
    Hash {
        path: PathBuf,
        #[arg(long, value_enum, default_value_t = HashAlgo::Blake3)]
        algo: HashAlgo,
    },
}

#[derive(Copy, Clone, ValueEnum)]
enum ModeArg {
    PathSize,
    PathSizeModified,
    PathSizeChecksum,
    Media,
    Phash,
}

impl From<ModeArg> for CompareMode {
    fn from(v: ModeArg) -> Self {
        match v {
            ModeArg::PathSize => CompareMode::PathSize,
            ModeArg::PathSizeModified => CompareMode::PathSizeModified,
            ModeArg::PathSizeChecksum => CompareMode::PathSizeChecksum,
            ModeArg::Media => CompareMode::MediaMetadata,
            ModeArg::Phash => CompareMode::PerceptualHash,
        }
    }
}

#[derive(Copy, Clone, ValueEnum)]
enum SyncModeArg {
    MirrorAToB,
    MirrorBToA,
    TwoWay,
}

impl From<SyncModeArg> for SyncMode {
    fn from(v: SyncModeArg) -> Self {
        match v {
            SyncModeArg::MirrorAToB => SyncMode::MirrorAToB,
            SyncModeArg::MirrorBToA => SyncMode::MirrorBToA,
            SyncModeArg::TwoWay => SyncMode::TwoWayNewerWins,
        }
    }
}

#[derive(Copy, Clone, ValueEnum)]
enum ConflictArg {
    NewerWins,
    LargerWins,
    Skip,
}

impl From<ConflictArg> for ConflictStrategy {
    fn from(v: ConflictArg) -> Self {
        match v {
            ConflictArg::NewerWins => ConflictStrategy::NewerWins,
            ConflictArg::LargerWins => ConflictStrategy::LargerWins,
            ConflictArg::Skip => ConflictStrategy::Skip,
        }
    }
}

#[derive(Copy, Clone, ValueEnum)]
enum OutputFormat {
    Text,
    Csv,
    Json,
}

#[derive(Copy, Clone, ValueEnum)]
enum HashAlgo {
    Blake3,
    Phash,
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match run(cli) {
        Ok(code) => code,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::from(2)
        }
    }
}

fn run(cli: Cli) -> anyhow::Result<ExitCode> {
    match cli.command {
        Command::Compare {
            folder_a,
            folder_b,
            mode,
            ignore_hidden,
            ignore,
            format,
            out,
            follow_symlinks,
            detect_renames,
            tolerance_mtime,
            tolerance_duration_ms,
            tolerance_phash,
        } => {
            let tolerance = CompareTolerance {
                mtime_secs: tolerance_mtime,
                duration_ms: tolerance_duration_ms,
                phash_hamming: tolerance_phash,
            };
            let mut callbacks = ProgressCallbacks::default();
            let report = compare_folders_with_progress(
                &folder_a,
                &folder_b,
                mode.into(),
                ignore_hidden,
                ignore,
                tolerance,
                follow_symlinks,
                detect_renames,
                &mut callbacks,
            )?;

            let output = match format {
                OutputFormat::Text => report_txt(&report, "SEDER Folder Compare"),
                OutputFormat::Csv => report_csv(&report),
                OutputFormat::Json => report_json(&report)?,
            };
            if let Some(path) = out {
                write_text(&path, &output)?;
            } else {
                print!("{output}");
            }

            let has_diffs = report
                .rows
                .iter()
                .any(|row| row.status != FileStatus::Matching)
                || !report.folders_only_in_a.is_empty()
                || !report.folders_only_in_b.is_empty();
            Ok(if has_diffs {
                ExitCode::from(1)
            } else {
                ExitCode::from(0)
            })
        }
        Command::Sync {
            folder_a,
            folder_b,
            mode,
            delete,
            dry_run,
            conflict,
        } => {
            let mut callbacks = ProgressCallbacks::default();
            // Sync needs a comparison first. Path+size is the cheapest mode.
            let report = compare_folders_with_progress(
                &folder_a,
                &folder_b,
                CompareMode::PathSize,
                true,
                vec![],
                CompareTolerance::default(),
                false,
                false,
                &mut callbacks,
            )?;
            let options = SyncOptions {
                propagate_deletes: delete,
                dry_run,
                conflict_strategy: conflict.into(),
            };
            let plan = build_sync_plan(&report, &folder_a, &folder_b, mode.into(), &options);
            println!("Planned {} action(s):", plan.len());
            for action in &plan.actions {
                println!(
                    "  {:?}  {} -> {}  ({})",
                    action.kind,
                    action.source.display(),
                    action.dest.display(),
                    action.reason
                );
            }
            if !dry_run {
                let mut cb = ProgressCallbacks::default();
                execute_sync_plan(&plan, &options, &mut cb)?;
                println!("Sync complete.");
            }
            Ok(ExitCode::from(0))
        }
        Command::Hash { path, algo } => {
            match algo {
                HashAlgo::Blake3 => {
                    let h = checksum_file(&path, ChecksumMethod::Blake3)?;
                    println!("{h}  {}", path.display());
                }
                HashAlgo::Phash => match probe_media(&path)? {
                    Some(info) => match info.phash {
                        Some(h) => println!("{h:016x}  {}", path.display()),
                        None => {
                            eprintln!("no perceptual hash available for {}", path.display());
                            return Ok(ExitCode::from(2));
                        }
                    },
                    None => {
                        eprintln!("not a recognized media file: {}", path.display());
                        return Ok(ExitCode::from(2));
                    }
                },
            }
            Ok(ExitCode::from(0))
        }
    }
}

fn report_json(report: &seder_folder_compare::CompareReport) -> anyhow::Result<String> {
    use serde_json::json;
    let rows: Vec<_> = report
        .rows
        .iter()
        .map(|r| {
            json!({
                "path": r.relative_path,
                "status": format!("{:?}", r.status),
                "size_a": r.size_a,
                "size_b": r.size_b,
                "checksum_a": r.checksum_a,
                "checksum_b": r.checksum_b,
                "rename_from": r.rename_from,
                "rename_to": r.rename_to,
            })
        })
        .collect();
    let value = json!({
        "total_files": report.total_files,
        "total_folders": report.total_folders,
        "total_size": report.total_size,
        "folders_only_in_a": report.folders_only_in_a,
        "folders_only_in_b": report.folders_only_in_b,
        "rows": rows,
    });
    Ok(serde_json::to_string_pretty(&value)?)
}
