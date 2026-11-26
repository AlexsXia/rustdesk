//! Self-hosted account service for the UU-style client.
//!
//! Implements the subset of the RustDesk account API the client uses for
//! register / login / logout, plus the legacy address book (`/api/ab`) which
//! is where the account's device list lives. Every device that logs in is
//! bound to the account and merged into the address book, so all clients of
//! the account see each other.
//!
//! Deployment: see README.md. Listens on `ACCOUNT_BIND` (default
//! 0.0.0.0:21114), stores data in `ACCOUNT_DB` (default account.db).

use std::{
    net::SocketAddr,
    sync::{Arc, Mutex},
    time::{SystemTime, UNIX_EPOCH},
};

use argon2::{
    password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use axum::{
    extract::{Path, State},
    http::{header::AUTHORIZATION, HeaderMap, StatusCode},
    response::{IntoResponse, Response},
    routing::{delete, get, post},
    Json, Router,
};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine as _};
use rand::RngCore;
use rusqlite::{params, Connection, ErrorCode, OptionalExtension};
use serde::Deserialize;
use serde_json::{json, Value};

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS users (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    name          TEXT NOT NULL COLLATE NOCASE UNIQUE,
    password_hash TEXT NOT NULL,
    display_name  TEXT NOT NULL DEFAULT '',
    avatar        TEXT NOT NULL DEFAULT '',
    note          TEXT NOT NULL DEFAULT '',
    status        INTEGER NOT NULL DEFAULT 1,
    is_admin      INTEGER NOT NULL DEFAULT 0,
    created_at    INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS tokens (
    token      TEXT PRIMARY KEY,
    user_id    INTEGER NOT NULL,
    created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_tokens_user ON tokens(user_id);
CREATE TABLE IF NOT EXISTS devices (
    id        TEXT PRIMARY KEY,
    uuid      TEXT NOT NULL DEFAULT '',
    name      TEXT NOT NULL DEFAULT '',
    os        TEXT NOT NULL DEFAULT '',
    username  TEXT NOT NULL DEFAULT '',
    last_seen INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS user_devices (
    user_id    INTEGER NOT NULL,
    device_id  TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    PRIMARY KEY (user_id, device_id)
);
CREATE TABLE IF NOT EXISTS address_books (
    user_id INTEGER PRIMARY KEY,
    data    TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS account_secrets (
    user_id    INTEGER PRIMARY KEY,
    secret     TEXT NOT NULL,
    created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS keymap_profiles (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER NOT NULL,
    name       TEXT NOT NULL,
    data       TEXT NOT NULL,
    is_public  INTEGER NOT NULL DEFAULT 1,
    updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_keymap_updated ON keymap_profiles(updated_at);
";

#[derive(Clone)]
struct AppState {
    db: Arc<Mutex<Connection>>,
}

#[derive(Debug)]
struct ApiError {
    status: StatusCode,
    message: String,
}

impl ApiError {
    fn new(status: StatusCode, message: impl Into<String>) -> Self {
        Self {
            status,
            message: message.into(),
        }
    }

    fn bad_request(message: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, message)
    }

    fn unauthorized() -> Self {
        Self::new(StatusCode::UNAUTHORIZED, "请先登录")
    }

    fn unauthorized_msg(message: impl Into<String>) -> Self {
        Self::new(StatusCode::UNAUTHORIZED, message)
    }

    fn conflict(message: impl Into<String>) -> Self {
        Self::new(StatusCode::CONFLICT, message)
    }

    fn internal(message: impl Into<String>) -> Self {
        Self::new(StatusCode::INTERNAL_SERVER_ERROR, message)
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.status, Json(json!({ "error": self.message }))).into_response()
    }
}

impl From<rusqlite::Error> for ApiError {
    fn from(err: rusqlite::Error) -> Self {
        Self::internal(format!("database error: {err}"))
    }
}

impl From<serde_json::Error> for ApiError {
    fn from(err: serde_json::Error) -> Self {
        Self::bad_request(format!("invalid json: {err}"))
    }
}

async fn with_db<T, F>(state: &AppState, f: F) -> Result<T, ApiError>
where
    T: Send + 'static,
    F: FnOnce(&Connection) -> Result<T, ApiError> + Send + 'static,
{
    let db = state.db.clone();
    tokio::task::spawn_blocking(move || {
        let conn = db
            .lock()
            .map_err(|_| ApiError::internal("database lock poisoned"))?;
        f(&conn)
    })
    .await
    .map_err(|err| ApiError::internal(format!("database task failed: {err}")))?
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or_default()
}

fn new_token() -> String {
    let mut bytes = [0u8; 32];
    rand::thread_rng().fill_bytes(&mut bytes);
    URL_SAFE_NO_PAD.encode(bytes)
}

/// One secret per account, mirrored by every signed-in device into its permanent
/// password, so devices of the same account can connect without a prompt.
fn account_device_secret(conn: &Connection, user_id: i64) -> Result<String, ApiError> {
    if let Some(secret) = conn
        .query_row(
            "SELECT secret FROM account_secrets WHERE user_id = ?1",
            params![user_id],
            |row| row.get::<_, String>(0),
        )
        .optional()?
    {
        return Ok(secret);
    }
    let secret = new_token();
    conn.execute(
        "INSERT INTO account_secrets(user_id, secret, created_at) VALUES(?1, ?2, ?3)",
        params![user_id, secret, now()],
    )?;
    Ok(secret)
}

fn hash_password(password: &str) -> Result<String, ApiError> {
    let mut salt_bytes = [0u8; 16];
    rand::thread_rng().fill_bytes(&mut salt_bytes);
    let salt = SaltString::encode_b64(&salt_bytes)
        .map_err(|err| ApiError::internal(format!("salt error: {err}")))?;
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map(|hash| hash.to_string())
        .map_err(|err| ApiError::internal(format!("hash error: {err}")))
}

fn verify_password(password: &str, stored: &str) -> bool {
    match PasswordHash::new(stored) {
        Ok(parsed) => Argon2::default()
            .verify_password(password.as_bytes(), &parsed)
            .is_ok(),
        Err(_) => false,
    }
}

fn validate_credentials(username: &str, password: &str) -> Result<(), ApiError> {
    let name_len = username.chars().count();
    if !(3..=64).contains(&name_len) {
        return Err(ApiError::bad_request("用户名长度需为 3-64 个字符"));
    }
    if !username
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-' | '@'))
    {
        return Err(ApiError::bad_request(
            "用户名只能包含字母、数字、点、下划线、横线或 @",
        ));
    }
    if password.chars().count() < 6 {
        return Err(ApiError::bad_request("密码至少需要 6 个字符"));
    }
    Ok(())
}

#[derive(Clone, Default, Deserialize)]
struct DeviceInfo {
    #[serde(default)]
    os: String,
    #[serde(default, rename = "type")]
    _kind: String,
    #[serde(default)]
    name: String,
}

#[derive(Deserialize)]
struct AuthReq {
    #[serde(default)]
    username: String,
    #[serde(default)]
    password: String,
    #[serde(default)]
    display_name: Option<String>,
    #[serde(default)]
    id: String,
    #[serde(default)]
    uuid: String,
    #[serde(default, rename = "deviceInfo")]
    device_info: DeviceInfo,
}

#[derive(Default, Deserialize)]
struct DeviceCtx {
    #[serde(default)]
    id: String,
    #[serde(default)]
    uuid: String,
}

#[derive(Deserialize)]
struct AbPush {
    #[serde(default)]
    data: String,
}

struct UserRow {
    id: i64,
    name: String,
    display_name: String,
    avatar: String,
    note: String,
    status: i64,
    is_admin: bool,
}

const USER_COLUMNS: &str = "id, name, display_name, avatar, note, status, is_admin";

fn user_from_row(row: &rusqlite::Row) -> rusqlite::Result<UserRow> {
    Ok(UserRow {
        id: row.get(0)?,
        name: row.get(1)?,
        display_name: row.get(2)?,
        avatar: row.get(3)?,
        note: row.get(4)?,
        status: row.get(5)?,
        is_admin: row.get::<_, i64>(6)? != 0,
    })
}

fn load_user_by_id(conn: &Connection, user_id: i64) -> Result<UserRow, ApiError> {
    conn.query_row(
        &format!("SELECT {USER_COLUMNS} FROM users WHERE id = ?1"),
        params![user_id],
        user_from_row,
    )
    .optional()?
    .ok_or_else(ApiError::unauthorized)
}

fn user_payload(user: &UserRow) -> Value {
    json!({
        "name": user.name,
        "display_name": user.display_name,
        "avatar": user.avatar,
        "email": Value::Null,
        "note": user.note,
        "status": user.status,
        "info": {
            "email_verification": false,
            "email_alarm_notification": false,
            "login_device_whitelist": [],
            "other": {}
        },
        "is_admin": user.is_admin
    })
}

fn auth_body(token: &str, user: &UserRow, device_secret: &str) -> Value {
    json!({
        "access_token": token,
        "type": "access_token",
        "tfa_type": "",
        "device_secret": device_secret,
        "user": user_payload(user)
    })
}

fn bearer_token(headers: &HeaderMap) -> Option<String> {
    let value = headers.get(AUTHORIZATION)?.to_str().ok()?;
    let token = value.strip_prefix("Bearer ")?.trim();
    if token.is_empty() {
        None
    } else {
        Some(token.to_owned())
    }
}

fn auth_user(conn: &Connection, headers: &HeaderMap) -> Result<UserRow, ApiError> {
    let token = bearer_token(headers).ok_or_else(ApiError::unauthorized)?;
    conn.query_row(
        &format!(
            "SELECT {} FROM users u JOIN tokens t ON t.user_id = u.id WHERE t.token = ?1",
            USER_COLUMNS
                .split(", ")
                .map(|c| format!("u.{c}"))
                .collect::<Vec<_>>()
                .join(", ")
        ),
        params![token],
        user_from_row,
    )
    .optional()?
    .ok_or_else(ApiError::unauthorized)
}

fn upsert_device(
    conn: &Connection,
    id: &str,
    uuid: &str,
    name: &str,
    os: &str,
    username: &str,
) -> Result<(), ApiError> {
    if id.is_empty() {
        return Ok(());
    }
    conn.execute(
        "INSERT INTO devices(id, uuid, name, os, username, last_seen)
         VALUES(?1, ?2, ?3, ?4, ?5, ?6)
         ON CONFLICT(id) DO UPDATE SET
             uuid = CASE WHEN excluded.uuid <> '' THEN excluded.uuid ELSE devices.uuid END,
             name = CASE WHEN excluded.name <> '' THEN excluded.name ELSE devices.name END,
             os = CASE WHEN excluded.os <> '' THEN excluded.os ELSE devices.os END,
             username = CASE WHEN excluded.username <> '' THEN excluded.username ELSE devices.username END,
             last_seen = excluded.last_seen",
        params![id, uuid, name, os, username, now()],
    )?;
    Ok(())
}

fn default_ab() -> Value {
    json!({
        "tags": [],
        "peers": [],
        "tag_colors": "{}"
    })
}

fn load_ab(conn: &Connection, user_id: i64) -> Result<Value, ApiError> {
    let data = conn
        .query_row(
            "SELECT data FROM address_books WHERE user_id = ?1",
            params![user_id],
            |row| row.get::<_, String>(0),
        )
        .optional()?;
    Ok(data
        .and_then(|raw| serde_json::from_str(&raw).ok())
        .unwrap_or_else(default_ab))
}

fn save_ab(conn: &Connection, user_id: i64, ab: &Value) -> Result<(), ApiError> {
    conn.execute(
        "INSERT INTO address_books(user_id, data) VALUES(?1, ?2)
         ON CONFLICT(user_id) DO UPDATE SET data = excluded.data",
        params![user_id, serde_json::to_string(ab)?],
    )?;
    Ok(())
}

struct DeviceRow {
    id: String,
    name: String,
    os: String,
    username: String,
}

fn normalize_platform(os: &str) -> String {
    let lower = os.to_lowercase();
    if lower.contains("android") {
        "Android".to_owned()
    } else if lower.contains("ios") || lower.contains("iphone") || lower.contains("ipad") {
        "iOS".to_owned()
    } else if lower.contains("mac") || lower.contains("darwin") {
        "Mac OS".to_owned()
    } else if lower.contains("win") {
        "Windows".to_owned()
    } else if lower.contains("linux") {
        "Linux".to_owned()
    } else {
        os.to_owned()
    }
}

fn upsert_peer(peers: &mut Vec<Value>, device: &DeviceRow, account_name: &str) {
    let platform = normalize_platform(&device.os);
    if let Some(peer) = peers
        .iter_mut()
        .find(|peer| peer.get("id").and_then(Value::as_str) == Some(device.id.as_str()))
    {
        if let Some(peer) = peer.as_object_mut() {
            if !device.name.is_empty() {
                peer.insert("hostname".to_owned(), json!(device.name));
            }
            if !platform.is_empty() {
                peer.insert("platform".to_owned(), json!(platform));
            }
            if !device.username.is_empty() {
                peer.insert("username".to_owned(), json!(device.username));
            }
            peer.insert("loginName".to_owned(), json!(account_name));
            peer.insert("same_server".to_owned(), json!(true));
        }
        return;
    }
    peers.push(json!({
        "id": device.id,
        "hash": "",
        "password": "",
        "username": device.username,
        "hostname": device.name,
        "platform": platform,
        "alias": "",
        "tags": [],
        "forceAlwaysRelay": "false",
        "rdpPort": "",
        "rdpUsername": "",
        "loginName": account_name,
        "device_group_name": "",
        "note": "",
        "same_server": true
    }));
}

fn merge_devices_into_ab(
    conn: &Connection,
    user_id: i64,
    account_name: &str,
    ab: &mut Value,
) -> Result<(), ApiError> {
    let mut stmt = conn.prepare(
        "SELECT d.id, d.name, d.os, d.username
         FROM devices d JOIN user_devices ud ON ud.device_id = d.id
         WHERE ud.user_id = ?1 ORDER BY ud.created_at",
    )?;
    let devices = stmt
        .query_map(params![user_id], |row| {
            Ok(DeviceRow {
                id: row.get(0)?,
                name: row.get(1)?,
                os: row.get(2)?,
                username: row.get(3)?,
            })
        })?
        .collect::<Result<Vec<_>, _>>()?;

    if !ab.is_object() {
        *ab = default_ab();
    }
    let Some(root) = ab.as_object_mut() else {
        return Ok(());
    };
    let peers_value = root.entry("peers").or_insert_with(|| json!([]));
    if !peers_value.is_array() {
        *peers_value = json!([]);
    }
    let Some(peers) = peers_value.as_array_mut() else {
        return Ok(());
    };
    for device in &devices {
        upsert_peer(peers, device, account_name);
    }
    Ok(())
}

fn remove_peer(ab: &mut Value, device_id: &str) {
    if let Some(peers) = ab.get_mut("peers").and_then(Value::as_array_mut) {
        peers.retain(|peer| peer.get("id").and_then(Value::as_str) != Some(device_id));
    }
}

/// A device can only belong to the account currently logged in on it. When a
/// different account logs in, drop the binding and the stale peer from the
/// previous account's address book.
fn unbind_other_users(conn: &Connection, user_id: i64, device_id: &str) -> Result<(), ApiError> {
    let mut stmt = conn.prepare(
        "SELECT ud.user_id FROM user_devices ud
         WHERE ud.device_id = ?1 AND ud.user_id != ?2",
    )?;
    let others = stmt
        .query_map(params![device_id, user_id], |row| row.get::<_, i64>(0))?
        .collect::<Result<Vec<_>, _>>()?;
    if others.is_empty() {
        return Ok(());
    }
    conn.execute(
        "DELETE FROM user_devices WHERE device_id = ?1 AND user_id != ?2",
        params![device_id, user_id],
    )?;
    for other_id in others {
        let mut ab = load_ab(conn, other_id)?;
        remove_peer(&mut ab, device_id);
        save_ab(conn, other_id, &ab)?;
    }
    Ok(())
}

fn bind_device(
    conn: &Connection,
    user: &UserRow,
    id: &str,
    uuid: &str,
    info: Option<&DeviceInfo>,
) -> Result<(), ApiError> {
    if id.is_empty() {
        return Ok(());
    }
    unbind_other_users(conn, user.id, id)?;
    let (name, os) = info
        .map(|info| (info.name.as_str(), info.os.as_str()))
        .unwrap_or_default();
    upsert_device(conn, id, uuid, name, os, "")?;
    conn.execute(
        "INSERT OR IGNORE INTO user_devices(user_id, device_id, created_at)
         VALUES(?1, ?2, ?3)",
        params![user.id, id, now()],
    )?;
    let mut ab = load_ab(conn, user.id)?;
    merge_devices_into_ab(conn, user.id, &user.name, &mut ab)?;
    save_ab(conn, user.id, &ab)?;
    Ok(())
}

async fn health() -> &'static str {
    "ok"
}

async fn login_options() -> Json<Value> {
    Json(json!([]))
}

async fn register(
    State(state): State<AppState>,
    Json(req): Json<AuthReq>,
) -> Result<Json<Value>, ApiError> {
    let username = req.username.trim().to_owned();
    let password = req.password;
    validate_credentials(&username, &password)?;
    let display_name = req.display_name.unwrap_or_default().trim().to_owned();
    let device_info = req.device_info;
    let device_id = req.id.trim().to_owned();
    let uuid = req.uuid.trim().to_owned();
    let password_hash = hash_password(&password)?;

    let body = with_db(&state, move |conn| {
        let created_at = now();
        let insert = conn.execute(
            "INSERT INTO users(name, password_hash, display_name, created_at)
             VALUES(?1, ?2, ?3, ?4)",
            params![username, password_hash, display_name, created_at],
        );
        match insert {
            Ok(_) => {}
            Err(err) => {
                if let rusqlite::Error::SqliteFailure(code, _) = &err {
                    if code.code == ErrorCode::ConstraintViolation {
                        return Err(ApiError::conflict("用户名已存在"));
                    }
                }
                return Err(err.into());
            }
        }
        let user_id = conn.last_insert_rowid();
        let user = load_user_by_id(conn, user_id)?;
        let token = new_token();
        conn.execute(
            "INSERT INTO tokens(token, user_id, created_at) VALUES(?1, ?2, ?3)",
            params![token, user_id, now()],
        )?;
        bind_device(conn, &user, &device_id, &uuid, Some(&device_info))?;
        let secret = account_device_secret(conn, user.id)?;
        Ok(auth_body(&token, &user, &secret))
    })
    .await?;
    Ok(Json(body))
}

async fn login(
    State(state): State<AppState>,
    Json(req): Json<AuthReq>,
) -> Result<Json<Value>, ApiError> {
    let username = req.username.trim().to_owned();
    let password = req.password;
    if username.is_empty() || password.is_empty() {
        return Err(ApiError::bad_request("请输入用户名和密码"));
    }
    let device_info = req.device_info;
    let device_id = req.id.trim().to_owned();
    let uuid = req.uuid.trim().to_owned();

    let body = with_db(&state, move |conn| {
        let row = conn
            .query_row(
                "SELECT id, password_hash FROM users WHERE name = ?1 COLLATE NOCASE",
                params![username],
                |row| Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?)),
            )
            .optional()?;
        let Some((user_id, password_hash)) = row else {
            return Err(ApiError::unauthorized_msg("用户名或密码错误"));
        };
        if !verify_password(&password, &password_hash) {
            return Err(ApiError::unauthorized_msg("用户名或密码错误"));
        }
        let user = load_user_by_id(conn, user_id)?;
        let token = new_token();
        conn.execute(
            "INSERT INTO tokens(token, user_id, created_at) VALUES(?1, ?2, ?3)",
            params![token, user_id, now()],
        )?;
        bind_device(conn, &user, &device_id, &uuid, Some(&device_info))?;
        let secret = account_device_secret(conn, user.id)?;
        Ok(auth_body(&token, &user, &secret))
    })
    .await?;
    Ok(Json(body))
}

async fn current_user(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(ctx): Json<DeviceCtx>,
) -> Result<Json<Value>, ApiError> {
    let body = with_db(&state, move |conn| {
        let user = auth_user(conn, &headers)?;
        bind_device(conn, &user, ctx.id.trim(), ctx.uuid.trim(), None)?;
        let mut payload = user_payload(&user);
        payload["device_secret"] = json!(account_device_secret(conn, user.id)?);
        Ok(payload)
    })
    .await?;
    Ok(Json(body))
}

async fn logout(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Value>, ApiError> {
    if let Some(token) = bearer_token(&headers) {
        with_db(&state, move |conn| {
            conn.execute("DELETE FROM tokens WHERE token = ?1", params![token])?;
            Ok(())
        })
        .await?;
    }
    Ok(Json(json!({})))
}

async fn ab_get(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Value>, ApiError> {
    let body = with_db(&state, move |conn| {
        let user = auth_user(conn, &headers)?;
        let mut ab = load_ab(conn, user.id)?;
        merge_devices_into_ab(conn, user.id, &user.name, &mut ab)?;
        Ok(json!({
            "data": serde_json::to_string(&ab)?,
            "licensed_devices": 0
        }))
    })
    .await?;
    Ok(Json(body))
}

async fn ab_post(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(push): Json<AbPush>,
) -> Result<Json<Value>, ApiError> {
    if push.data.is_empty() {
        return Ok(Json(Value::Null));
    }
    let mut ab: Value = serde_json::from_str(&push.data)?;
    with_db(&state, move |conn| {
        let user = auth_user(conn, &headers)?;
        merge_devices_into_ab(conn, user.id, &user.name, &mut ab)?;
        save_ab(conn, user.id, &ab)?;
        Ok(())
    })
    .await?;
    Ok(Json(Value::Null))
}

async fn not_supported() -> impl IntoResponse {
    (
        StatusCode::NOT_FOUND,
        Json(json!({ "error": "not supported" })),
    )
}

async fn heartbeat(
    State(state): State<AppState>,
    Json(body): Json<Value>,
) -> Result<Json<Value>, ApiError> {
    let id = body.get("id").and_then(Value::as_str).unwrap_or_default();
    let uuid = body.get("uuid").and_then(Value::as_str).unwrap_or_default();
    let id = id.to_owned();
    let uuid = uuid.to_owned();
    with_db(&state, move |conn| {
        upsert_device(conn, &id, &uuid, "", "", "")?;
        Ok(())
    })
    .await?;
    Ok(Json(json!({})))
}

async fn sysinfo(
    State(state): State<AppState>,
    Json(body): Json<Value>,
) -> Result<String, ApiError> {
    let text = |key: &str| {
        body.get(key)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned()
    };
    let id = text("id");
    let uuid = text("uuid");
    let mut name = text("hostname");
    if name.is_empty() {
        name = text("device_name");
    }
    let mut os = text("os");
    if os.is_empty() {
        os = text("platform");
    }
    let username = text("username");
    with_db(&state, move |conn| {
        upsert_device(conn, &id, &uuid, &name, &os, &username)?;
        let mut stmt = conn.prepare(
            "SELECT u.id, u.name FROM users u
             JOIN user_devices ud ON ud.user_id = u.id
             WHERE ud.device_id = ?1",
        )?;
        let users = stmt
            .query_map(params![id], |row| {
                Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        for (user_id, user_name) in users {
            let mut ab = load_ab(conn, user_id)?;
            merge_devices_into_ab(conn, user_id, &user_name, &mut ab)?;
            save_ab(conn, user_id, &ab)?;
        }
        Ok(())
    })
    .await?;
    Ok(String::new())
}

async fn device_groups(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Value>, ApiError> {
    with_db(&state, move |conn| {
        auth_user(conn, &headers)?;
        Ok(())
    })
    .await?;
    Ok(Json(json!({ "total": 0, "data": [] })))
}

async fn users(State(state): State<AppState>, headers: HeaderMap) -> Result<Json<Value>, ApiError> {
    let body = with_db(&state, move |conn| {
        let user = auth_user(conn, &headers)?;
        Ok(json!({
            "total": 1,
            "data": [user_payload(&user)]
        }))
    })
    .await?;
    Ok(Json(body))
}

async fn peers(State(state): State<AppState>, headers: HeaderMap) -> Result<Json<Value>, ApiError> {
    let body = with_db(&state, move |conn| {
        let user = auth_user(conn, &headers)?;
        let mut stmt = conn.prepare(
            "SELECT d.id, d.name, d.os, d.username
             FROM devices d JOIN user_devices ud ON ud.device_id = d.id
             WHERE ud.user_id = ?1 ORDER BY ud.created_at",
        )?;
        let devices = stmt
            .query_map(params![user.id], |row| {
                Ok(DeviceRow {
                    id: row.get(0)?,
                    name: row.get(1)?,
                    os: row.get(2)?,
                    username: row.get(3)?,
                })
            })?
            .collect::<Result<Vec<_>, _>>()?;
        let data: Vec<Value> = devices
            .iter()
            .map(|device| {
                json!({
                    "id": device.id,
                    "info": {
                        "os": device.os,
                        "device_name": device.name,
                        "username": device.username
                    },
                    "status": 1,
                    "user": user.name,
                    "user_name": user.name,
                    "device_group_name": "",
                    "note": ""
                })
            })
            .collect();
        Ok(json!({ "total": data.len(), "data": data }))
    })
    .await?;
    Ok(Json(body))
}

#[derive(Deserialize)]
struct KeymapPush {
    id: Option<i64>,
    name: String,
    data: String,
}

async fn keymap_list(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> Result<Json<Value>, ApiError> {
    let body = with_db(&state, move |conn| {
        let user = auth_user(conn, &headers)?;
        let mut stmt = conn.prepare(
            "SELECT k.id, k.name, k.data, k.updated_at,
                    COALESCE(NULLIF(u.display_name, ''), u.name)
             FROM keymap_profiles k JOIN users u ON u.id = k.user_id
             WHERE k.is_public = 1 OR k.user_id = ?1
             ORDER BY k.updated_at DESC LIMIT 200",
        )?;
        let profiles = stmt
            .query_map(params![user.id], |row| {
                Ok(json!({
                    "id": row.get::<_, i64>(0)?,
                    "name": row.get::<_, String>(1)?,
                    "data": row.get::<_, String>(2)?,
                    "updated_at": row.get::<_, i64>(3)?,
                    "author": row.get::<_, String>(4)?,
                }))
            })?
            .collect::<Result<Vec<_>, _>>()?;
        Ok(json!({ "profiles": profiles }))
    })
    .await?;
    Ok(Json(body))
}

async fn keymap_push(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(push): Json<KeymapPush>,
) -> Result<Json<Value>, ApiError> {
    let name = push.name.trim().to_owned();
    if name.is_empty() || name.chars().count() > 40 {
        return Err(ApiError::bad_request("方案名称不能为空且不超过 40 个字"));
    }
    if push.data.len() > 64 * 1024 {
        return Err(ApiError::bad_request("方案数据过大"));
    }
    serde_json::from_str::<Value>(&push.data)?;
    let id = with_db(&state, move |conn| {
        let user = auth_user(conn, &headers)?;
        let id = if let Some(id) = push.id {
            let updated = conn.execute(
                "UPDATE keymap_profiles SET name = ?1, data = ?2, updated_at = ?3
                 WHERE id = ?4 AND user_id = ?5",
                params![name, push.data, now(), id, user.id],
            )?;
            if updated == 0 {
                return Err(ApiError::new(StatusCode::NOT_FOUND, "方案不存在"));
            }
            id
        } else {
            conn.execute(
                "INSERT INTO keymap_profiles(user_id, name, data, is_public, updated_at)
                 VALUES(?1, ?2, ?3, 1, ?4)",
                params![user.id, name, push.data, now()],
            )?;
            conn.last_insert_rowid()
        };
        Ok(id)
    })
    .await?;
    Ok(Json(json!({ "id": id })))
}

async fn keymap_delete(
    State(state): State<AppState>,
    Path(id): Path<i64>,
    headers: HeaderMap,
) -> Result<Json<Value>, ApiError> {
    with_db(&state, move |conn| {
        let user = auth_user(conn, &headers)?;
        conn.execute(
            "DELETE FROM keymap_profiles WHERE id = ?1 AND user_id = ?2",
            params![id, user.id],
        )?;
        Ok(())
    })
    .await?;
    Ok(Json(json!({})))
}

async fn not_found() -> impl IntoResponse {
    (StatusCode::NOT_FOUND, Json(json!({ "error": "not found" })))
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let db_path = std::env::var("ACCOUNT_DB").unwrap_or_else(|_| "account.db".to_owned());
    let bind = std::env::var("ACCOUNT_BIND").unwrap_or_else(|_| "0.0.0.0:21114".to_owned());

    let conn = Connection::open(&db_path)?;
    conn.query_row("PRAGMA journal_mode=WAL", [], |_| Ok(()))?;
    conn.execute_batch("PRAGMA busy_timeout=5000; PRAGMA synchronous=NORMAL;")?;
    conn.execute_batch(SCHEMA)?;

    let state = AppState {
        db: Arc::new(Mutex::new(conn)),
    };

    let app = Router::new()
        .route("/api/health", get(health))
        .route("/api/login-options", get(login_options))
        .route("/api/register", post(register))
        .route("/api/login", post(login))
        .route("/api/currentUser", post(current_user))
        .route("/api/logout", post(logout))
        .route("/api/ab", get(ab_get).post(ab_post))
        .route("/api/ab/personal", post(not_supported))
        .route("/api/ab/settings", post(not_supported))
        .route("/api/ab/shared/profiles", post(not_supported))
        .route("/api/heartbeat", post(heartbeat))
        .route("/api/sysinfo", post(sysinfo))
        .route("/api/device-group/accessible", get(device_groups))
        .route("/api/users", get(users))
        .route("/api/peers", get(peers))
        .route("/api/keymap/profiles", get(keymap_list).post(keymap_push))
        .route("/api/keymap/profiles/{id}", delete(keymap_delete))
        .fallback(not_found)
        .with_state(state);

    let addr: SocketAddr = bind.parse()?;
    let listener = tokio::net::TcpListener::bind(addr).await?;
    println!("account server listening on {addr}, db: {db_path}");
    axum::serve(listener, app).await?;
    Ok(())
}
