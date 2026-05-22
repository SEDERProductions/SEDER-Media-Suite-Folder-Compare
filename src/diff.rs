// SPDX-License-Identifier: GPL-3.0-only
#![forbid(unsafe_code)]

//! Per-file diff helpers used by the content-diff view.
//!
//! `diff_text` returns line-level hunks for two text files via the `similar`
//! crate. `hex_window` returns a slice of a file's bytes; the UI is responsible
//! for diffing the two windows visually.

use anyhow::{Context, Result};
use similar::{ChangeTag, TextDiff};
use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LineKind {
    Equal,
    Insert,
    Delete,
}

#[derive(Debug, Clone)]
pub struct DiffLine {
    pub kind: LineKind,
    pub line_a: Option<u32>,
    pub line_b: Option<u32>,
    pub text: String,
}

/// True if the file looks like plain text: valid UTF-8 and at least 95% printable
/// characters (or accepted whitespace) in the first 8 KiB.
pub fn is_text_file(path: &Path) -> bool {
    let mut buf = vec![0u8; 8192];
    let n = match fs::File::open(path).and_then(|mut f| f.read(&mut buf)) {
        Ok(n) => n,
        Err(_) => return false,
    };
    let slice = &buf[..n];
    // NUL bytes are a strong signal that this is binary data.
    if slice.contains(&0) {
        return false;
    }

    let text = match std::str::from_utf8(slice) {
        Ok(text) => text,
        Err(_) => return false,
    };
    if text.is_empty() {
        return true;
    }

    // Treat Unicode letters/numbers/punctuation/symbols/whitespace as printable
    // while excluding a small set of common binary-ish control characters.
    let printable = text
        .chars()
        .filter(|&ch| {
            if matches!(
                ch,
                '\u{0007}' | '\u{0008}' | '\u{000B}' | '\u{000C}' | '\u{007F}'
            ) {
                return false;
            }
            ch.is_alphanumeric() || ch.is_whitespace() || !ch.is_control()
        })
        .count();
    let total = text.chars().count();
    (printable * 100) / total >= 95
}

/// Line-level diff of two text files.
pub fn diff_text(a: &Path, b: &Path) -> Result<Vec<DiffLine>> {
    let text_a =
        fs::read_to_string(a).with_context(|| format!("reading {} as UTF-8 text", a.display()))?;
    let text_b =
        fs::read_to_string(b).with_context(|| format!("reading {} as UTF-8 text", b.display()))?;

    let diff = TextDiff::from_lines(&text_a, &text_b);
    let mut out = Vec::new();
    for change in diff.iter_all_changes() {
        let kind = match change.tag() {
            ChangeTag::Equal => LineKind::Equal,
            ChangeTag::Delete => LineKind::Delete,
            ChangeTag::Insert => LineKind::Insert,
        };
        out.push(DiffLine {
            kind,
            line_a: change.old_index().map(|i| (i as u32) + 1),
            line_b: change.new_index().map(|i| (i as u32) + 1),
            text: change.value().trim_end_matches('\n').to_string(),
        });
    }
    Ok(out)
}

/// Read a window of bytes from `path` starting at `offset`.
pub fn hex_window(path: &Path, offset: u64, length: usize) -> Result<Vec<u8>> {
    let mut file = fs::File::open(path).with_context(|| format!("opening {}", path.display()))?;
    file.seek(SeekFrom::Start(offset))?;
    let mut buf = vec![0u8; length];
    let n = file.read(&mut buf)?;
    buf.truncate(n);
    Ok(buf)
}
