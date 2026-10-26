use base64::{engine::general_purpose::STANDARD, Engine};
use rand::RngCore;
use serde::de::DeserializeOwned;
use sha2::{Digest, Sha256};
use worker::{Error, Request, Response, Result};

pub(crate) const ITERATIONS: u32 = 600_000;
pub(crate) const SESSION_DAYS: i64 = 30;
const MAX_BODY: usize = 16 * 1024;

pub(crate) async fn read_json<T: DeserializeOwned>(request: &mut Request) -> Result<T> {
    read_json_with_limit(request, MAX_BODY).await
}

pub(crate) async fn read_json_with_limit<T: DeserializeOwned>(
    request: &mut Request,
    max_body: usize,
) -> Result<T> {
    let body = request.bytes().await?;
    if body.is_empty() || body.len() > max_body {
        return Err(Error::RustError("invalid body".into()));
    }
    serde_json::from_slice(&body).map_err(|_| Error::RustError("invalid JSON".into()))
}

pub(crate) fn valid_username(value: &str) -> bool {
    (4..=32).contains(&value.chars().count())
        && value.chars().all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '_' | '-' | '@' | '.')
        })
}

pub(crate) fn verifier_hash(verifier_base64: &str) -> Option<String> {
    let verifier = STANDARD.decode(verifier_base64).ok()?;
    (verifier.len() == 32).then(|| sha256_hex(&verifier))
}

pub(crate) fn valid_password_parameters(salt: &str, iterations: u32) -> bool {
    STANDARD.decode(salt).is_ok_and(|value| value.len() >= 16) && iterations == ITERATIONS
}

pub(crate) fn random_hex(size: usize) -> String {
    let mut bytes = vec![0; size];
    rand::thread_rng().fill_bytes(&mut bytes);
    hex(&bytes)
}

pub(crate) fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

pub(crate) fn sha256_hex(bytes: &[u8]) -> String {
    hex(&Sha256::digest(bytes))
}

pub(crate) fn constant_time_eq(left: &[u8], right: &[u8]) -> bool {
    if left.len() != right.len() {
        return false;
    }
    left.iter()
        .zip(right)
        .fold(0_u8, |diff, (a, b)| diff | (a ^ b))
        == 0
}

pub(crate) fn now() -> i64 {
    (js_sys::Date::now() / 1000.0).floor() as i64
}

pub(crate) fn uuid() -> String {
    let mut bytes = [0_u8; 16];
    rand::thread_rng().fill_bytes(&mut bytes);
    format!(
        "{}-{}-4{}-a{}-{}",
        hex(&bytes[..4]),
        hex(&bytes[4..6]),
        hex(&bytes[6..7]),
        hex(&bytes[7..8]),
        hex(&bytes[8..])
    )
}

pub(crate) fn bearer(request: &Request) -> Result<Option<String>> {
    Ok(request
        .headers()
        .get("Authorization")?
        .and_then(|value| value.strip_prefix("Bearer ").map(str::to_owned))
        .filter(|value| (32..=128).contains(&value.len())))
}

pub(crate) fn error(message: &str, status: u16) -> Result<Response> {
    Response::error(message, status)
}

pub(crate) fn secure_headers(mut response: Response) -> Result<Response> {
    response.headers_mut().set("Cache-Control", "no-store")?;
    response
        .headers_mut()
        .set("X-Content-Type-Options", "nosniff")?;
    response
        .headers_mut()
        .set("Access-Control-Allow-Origin", "*")?;
    response.headers_mut().set(
        "Access-Control-Allow-Methods",
        "GET, POST, PATCH, DELETE, OPTIONS",
    )?;
    response.headers_mut().set(
        "Access-Control-Allow-Headers",
        "Authorization, Content-Type, X-Bootstrap-Secret",
    )?;
    Ok(response)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_credentials() {
        assert!(valid_username("student_01"));
        assert!(valid_username("user"));
        assert!(valid_username("xzl@hbwhslxxpzxq202406"));
        assert!(!valid_username("abc"));
        assert!(!valid_username("student name"));
        assert!(!valid_username("student/name"));
        assert!(!valid_username("学生01"));
        assert!(valid_username("student.name"));
    }

    #[test]
    fn verifier_hash_requires_32_bytes() {
        assert!(verifier_hash(&STANDARD.encode([1_u8; 32])).is_some());
        assert!(verifier_hash(&STANDARD.encode([1_u8; 12])).is_none());
    }

    #[test]
    fn password_parameters_require_supported_salt_and_iteration_count() {
        assert!(valid_password_parameters(
            &STANDARD.encode([7_u8; 16]),
            ITERATIONS
        ));
        assert!(!valid_password_parameters(
            &STANDARD.encode([7_u8; 8]),
            ITERATIONS
        ));
        assert!(!valid_password_parameters(
            &STANDARD.encode([7_u8; 16]),
            ITERATIONS - 1
        ));
    }

    #[test]
    fn compares_hashes_without_early_exit() {
        assert!(constant_time_eq(b"same", b"same"));
        assert!(!constant_time_eq(b"same", b"diff"));
    }
}
