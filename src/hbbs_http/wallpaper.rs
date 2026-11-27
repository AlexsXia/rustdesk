//! Uploads a downscaled copy of the desktop wallpaper to the account server,
//! so the account's other devices can show it as this device's preview image.

use std::time::Duration;

use hbb_common::{
    anyhow::anyhow,
    base64::{engine::general_purpose::STANDARD, Engine as _},
    config::Config,
    tokio,
    ResultType,
};

const MAX_WIDTH: u32 = 1280;
const START_DELAY: Duration = Duration::from_secs(60);
const UPLOAD_INTERVAL: Duration = Duration::from_secs(6 * 60 * 60);
const RETRY_INTERVAL: Duration = Duration::from_secs(5 * 60);
const ERROR_LOG_INTERVAL: Duration = Duration::from_secs(30 * 60);

pub fn start() {
    tokio::spawn(async move {
        tokio::time::sleep(START_DELAY).await;
        loop {
            match upload_once().await {
                Ok(()) => tokio::time::sleep(UPLOAD_INTERVAL).await,
                Err(err) => {
                    hbb_common::throttled_log!(
                        ERROR_LOG_INTERVAL,
                        info,
                        "Wallpaper upload skipped: {err}"
                    );
                    tokio::time::sleep(RETRY_INTERVAL).await;
                }
            }
        }
    });
}

async fn upload_once() -> ResultType<()> {
    let url = wallpaper_url();
    if url.is_empty() {
        return Ok(());
    }
    let id = Config::get_id();
    if id.is_empty() {
        return Ok(());
    }
    let jpeg = tokio::task::spawn_blocking(wallpaper_jpeg)
        .await?
        .ok_or_else(|| anyhow!("no wallpaper image"))?;
    let body = serde_json::json!({
        "id": id,
        "uuid": crate::encode64(hbb_common::get_uuid()),
        "data": STANDARD.encode(&jpeg),
    })
    .to_string();
    let (status, _) = crate::post_request_with_status(url, body, "").await?;
    if !(200..300).contains(&status) {
        return Err(anyhow!("HTTP {status}"));
    }
    Ok(())
}

fn wallpaper_url() -> String {
    let url = crate::common::get_api_server(
        Config::get_option("api-server"),
        Config::get_option("custom-rendezvous-server"),
    );
    if url.is_empty() || crate::common::is_public(&url) {
        return "".to_owned();
    }
    format!("{url}/api/wallpaper")
}

fn wallpaper_jpeg() -> Option<Vec<u8>> {
    let path = platform_wallpaper_path()?;
    let bytes = std::fs::read(&path).unwrap_or_default();
    let image = image::load_from_memory(&bytes)
        .ok()
        .or_else(|| decode_with_sips(&path))?;
    let image = if image.width() > MAX_WIDTH {
        image.resize(MAX_WIDTH, u32::MAX, image::imageops::FilterType::Triangle)
    } else {
        image
    };
    let mut out = Vec::new();
    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut out, 80)
        .encode_image(&image)
        .ok()?;
    Some(out)
}

#[cfg(target_os = "macos")]
fn platform_wallpaper_path() -> Option<String> {
    crate::platform::macos::get_wallpaper_path()
}

#[cfg(target_os = "windows")]
fn platform_wallpaper_path() -> Option<String> {
    crate::platform::windows::get_wallpaper_path()
}

#[cfg(target_os = "linux")]
fn platform_wallpaper_path() -> Option<String> {
    crate::platform::linux::get_wallpaper_path()
}

#[cfg(target_os = "macos")]
fn decode_with_sips(path: &str) -> Option<image::DynamicImage> {
    let out = std::env::temp_dir().join("uu-wallpaper-preview.jpg");
    let status = std::process::Command::new("/usr/bin/sips")
        .args([
            "-s",
            "format",
            "jpeg",
            "--resampleWidth",
            "1280",
            path,
            "--out",
        ])
        .arg(&out)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .ok()?;
    if !status.success() {
        return None;
    }
    image::load_from_memory(&std::fs::read(&out).ok()?).ok()
}

#[cfg(not(target_os = "macos"))]
fn decode_with_sips(_path: &str) -> Option<image::DynamicImage> {
    None
}
