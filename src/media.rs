// SPDX-License-Identifier: GPL-3.0-only
#![forbid(unsafe_code)]

//! Media-aware probing: image dimensions + EXIF, audio/video duration + codec,
//! and perceptual hashing for images.
//!
//! Implementations are pure-Rust so cross-compilation stays simple. ffmpeg is
//! deliberately avoided.

use anyhow::Result;
use std::path::Path;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaKind {
    Image,
    Audio,
    Video,
    Other,
}

#[derive(Debug, Clone)]
pub struct MediaInfo {
    pub kind: MediaKind,
    pub width: Option<u32>,
    pub height: Option<u32>,
    pub duration_ms: Option<u32>,
    pub sample_rate: Option<u32>,
    pub codec: Option<String>,
    pub exif_datetime: Option<String>,
    pub phash: Option<u64>,
}

fn classify_by_extension(path: &Path) -> MediaKind {
    let ext = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_ascii_lowercase())
        .unwrap_or_default();
    match ext.as_str() {
        "jpg" | "jpeg" | "png" | "gif" | "bmp" | "webp" | "tif" | "tiff" => MediaKind::Image,
        "wav" | "mp3" | "flac" | "ogg" | "oga" | "aac" | "m4a" | "aiff" | "aif" | "wv" | "ape" => {
            MediaKind::Audio
        }
        "mp4" | "mov" | "mkv" | "avi" | "webm" | "m4v" | "mxf" | "wmv" | "ts" => MediaKind::Video,
        _ => MediaKind::Other,
    }
}

/// Probe a path for media-intrinsic metadata. Returns `Ok(None)` for non-media files.
pub fn probe(path: &Path) -> Result<Option<MediaInfo>> {
    match classify_by_extension(path) {
        MediaKind::Image => Ok(Some(probe_image(path)?)),
        MediaKind::Audio | MediaKind::Video => Ok(Some(probe_media_file(path)?)),
        MediaKind::Other => Ok(None),
    }
}

fn probe_image(path: &Path) -> Result<MediaInfo> {
    let mut info = MediaInfo {
        kind: MediaKind::Image,
        width: None,
        height: None,
        duration_ms: None,
        sample_rate: None,
        codec: None,
        exif_datetime: None,
        phash: None,
    };

    if let Ok(reader) = image::ImageReader::open(path) {
        if let Ok(reader) = reader.with_guessed_format() {
            if let Ok((w, h)) = reader.into_dimensions() {
                info.width = Some(w);
                info.height = Some(h);
            }
        }
    }

    if let Ok(file) = std::fs::File::open(path) {
        let mut bufreader = std::io::BufReader::new(file);
        let exif_reader = exif::Reader::new();
        if let Ok(exif) = exif_reader.read_from_container(&mut bufreader) {
            if let Some(field) = exif.get_field(exif::Tag::DateTimeOriginal, exif::In::PRIMARY) {
                info.exif_datetime = Some(field.display_value().to_string());
            }
        }
    }

    info.phash = compute_phash(path);
    Ok(info)
}

fn compute_phash(path: &Path) -> Option<u64> {
    // img_hash 3.2 ships its own copy of `image` 0.23; the loader and Hasher must
    // agree on which version. Avoid the version-clash with `image` 0.25 by routing
    // through img_hash's re-exported types.
    let img = img_hash::image::open(path).ok()?;
    let hasher = img_hash::HasherConfig::new()
        .hash_size(8, 8)
        .hash_alg(img_hash::HashAlg::Mean)
        .to_hasher();
    let hash = hasher.hash_image(&img);
    let bytes = hash.as_bytes();
    if bytes.len() < 8 {
        return None;
    }
    let mut buf = [0u8; 8];
    buf.copy_from_slice(&bytes[..8]);
    Some(u64::from_be_bytes(buf))
}

fn probe_media_file(path: &Path) -> Result<MediaInfo> {
    use symphonia::core::formats::FormatOptions;
    use symphonia::core::io::MediaSourceStream;
    use symphonia::core::meta::MetadataOptions;
    use symphonia::core::probe::Hint;

    let kind = classify_by_extension(path);
    let mut info = MediaInfo {
        kind,
        width: None,
        height: None,
        duration_ms: None,
        sample_rate: None,
        codec: None,
        exif_datetime: None,
        phash: None,
    };

    let file = match std::fs::File::open(path) {
        Ok(f) => f,
        Err(_) => return Ok(info),
    };
    let mss = MediaSourceStream::new(Box::new(file), Default::default());

    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }

    let probed = match symphonia::default::get_probe().format(
        &hint,
        mss,
        &FormatOptions::default(),
        &MetadataOptions::default(),
    ) {
        Ok(p) => p,
        Err(_) => return Ok(info),
    };

    let format = probed.format;
    if let Some(track) = format.default_track() {
        let cp = &track.codec_params;
        info.sample_rate = cp.sample_rate;
        info.codec = Some(format!("{:?}", cp.codec));
        if let (Some(n_frames), Some(rate)) = (cp.n_frames, cp.sample_rate) {
            if rate > 0 {
                let secs = n_frames as f64 / rate as f64;
                info.duration_ms = Some((secs * 1000.0) as u32);
            }
        }
        if let (Some(tb), Some(n_frames)) = (cp.time_base, cp.n_frames) {
            if info.duration_ms.is_none() {
                let secs = tb.calc_time(n_frames).seconds as f64 + tb.calc_time(n_frames).frac;
                info.duration_ms = Some((secs * 1000.0) as u32);
            }
        }
    }

    Ok(info)
}
