use crate::*;
use base64::{engine::general_purpose::STANDARD, Engine};
use worker::{Env, Request, Response, Result};

pub(super) async fn parameters(request: &mut Request, env: &Env) -> Result<Response> {
    let input: PasswordParametersRequest = match read_json(request).await {
        Ok(v) => v,
        Err(_) => return error("invalid request", 400),
    };
    let (salt, iterations) =
        match crate::db::accounts::find_by_username(&env.d1("DB")?, &input.username).await? {
            Some(account) => (account.password_salt, account.password_iterations),
            None => (
                STANDARD.encode(
                    &sha256_bytes(format!("unknown:{}", input.username.to_lowercase()).as_bytes())
                        [..16],
                ),
                ITERATIONS,
            ),
        };
    Response::from_json(&PasswordParameters { salt, iterations })
}

pub(super) async fn current_account(request: &Request, env: &Env) -> Result<Option<Account>> {
    let Some(token) = bearer(request)? else {
        return Ok(None);
    };
    crate::db::sessions::find_account(&env.d1("DB")?, &token, now()).await
}

pub(super) async fn register(request: &mut Request, env: &Env) -> Result<Response> {
    let input: Credentials = match read_json(request).await {
        Ok(v) => v,
        Err(_) => return error("invalid request", 400),
    };
    if !valid_username(&input.username) {
        return error("用户名需为 4–32 位，只能包含英文字母、数字及 _ - @", 400);
    }
    if !valid_password_parameters(&input.salt, input.iterations)
        || verifier_hash(&input.verifier).is_none()
    {
        return error("密码参数无效，请重新输入密码后重试", 400);
    }
    let id = match crate::db::accounts::insert(
        &env.d1("DB")?,
        &input.username,
        input.display_name.as_deref().unwrap_or(&input.username),
        "student",
        None,
        &input.salt,
        &input.verifier,
        input.iterations,
        false,
    )
    .await
    {
        Ok(id) => id,
        Err(_) => return error("username already exists or registration failed", 409),
    };
    Response::from_json(&serde_json::json!({"id":id,"role":"student"})).map(|r| r.with_status(201))
}

pub(super) async fn login(request: &mut Request, env: &Env) -> Result<Response> {
    let input: LoginRequest = match read_json(request).await {
        Ok(v) => v,
        Err(_) => return error("invalid username or password", 401),
    };
    let db = env.d1("DB")?;
    let Some(account) = crate::db::accounts::find_by_username(&db, &input.username).await? else {
        return error("invalid username or password", 401);
    };
    let actual = verifier_hash(&input.verifier).unwrap_or_default();
    if account.disabled != 0
        || !valid_password_parameters(&input.salt, input.iterations)
        || !constant_time_eq(input.salt.as_bytes(), account.password_salt.as_bytes())
        || input.iterations != account.password_iterations
        || !constant_time_eq(actual.as_bytes(), account.password_hash.as_bytes())
    {
        return error("invalid username or password", 401);
    }
    let token = random_hex(32);
    let expires = now() + SESSION_DAYS * 86400;
    crate::db::sessions::create(&db, &token, &account.id, expires).await?;
    Response::from_json(&LoginResponse {
        token,
        expires_at: expires,
        account: crate::db::accounts::view(&account),
    })
}

fn sha256_bytes(value: &[u8]) -> [u8; 32] {
    use sha2::{Digest, Sha256};
    Sha256::digest(value).into()
}

pub(super) async fn logout(request: &Request, env: &Env) -> Result<Response> {
    let Some(token) = bearer(request)? else {
        return error("unauthorized", 401);
    };
    crate::db::sessions::revoke_token(&env.d1("DB")?, &token).await?;
    Response::from_json(&serde_json::json!({"ok":true}))
}
