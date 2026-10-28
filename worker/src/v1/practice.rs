use super::auth::current_account;
use crate::*;
use base64::{engine::general_purpose::STANDARD, Engine};
use flate2::read::GzDecoder;
use serde::Deserialize;
use std::io::Read;
use worker::{Env, Request, Response, Result};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PracticeRecordInput {
    id: String,
    textbook_key: String,
    question_id: String,
    chapter_id: String,
    question_kind: String,
    category: String,
    source: String,
    direction: String,
    prompt: String,
    student_answer: String,
    expected_answer: String,
    is_correct: bool,
    occurred_at: String,
    handwriting_gzip: Option<String>,
    ocr_results: Option<Vec<String>>,
    review_bits: Option<String>,
    speech_snac: Option<String>,
    speech_review_bits: Option<String>,
    speech_recognized_pinyin: Option<String>,
}

pub(super) async fn record(request: &mut Request, env: &Env) -> Result<Response> {
    let Some(student) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if student.role != "student" {
        return error("only student accounts can upload practice records", 403);
    }
    let input: PracticeRecordInput = match read_json_with_limit(request, 128 * 1024).await {
        Ok(value) => value,
        Err(_) => return error("invalid practice record", 400),
    };
    if !valid_input(&input) {
        return error("做题记录字段无效", 400);
    }
    let db = env.d1("DB")?;
    let class_id = crate::db::class_memberships::find_class_for_student_at(
        &db,
        &student.id,
        &input.occurred_at,
    )
    .await?;
    let record = crate::db::practice_records::PracticeRecord {
        id: input.id,
        student_id: student.id.clone(),
        class_id: class_id.clone(),
        textbook_key: input.textbook_key,
        question_id: input.question_id,
        chapter_id: input.chapter_id,
        question_kind: input.question_kind,
        category: input.category,
        source: input.source,
        direction: input.direction,
        prompt: input.prompt,
        student_answer: input.student_answer,
        expected_answer: input.expected_answer,
        is_correct: if input.is_correct { 1 } else { 0 },
        occurred_at: input.occurred_at,
        created_at: String::new(),
        handwriting_gzip: input
            .handwriting_gzip
            .as_deref()
            .and_then(decode_valid_handwriting)
            .map(Into::into),
        ocr_results: input
            .ocr_results
            .map(|items| serde_json::to_string(&items).unwrap_or_default()),
        review_bits: input
            .review_bits
            .as_deref()
            .and_then(|value| STANDARD.decode(value).ok())
            .map(Into::into),
        speech_snac: input
            .speech_snac
            .as_deref()
            .and_then(decode_valid_snac)
            .map(Into::into),
        speech_review_bits: input
            .speech_review_bits
            .as_deref()
            .and_then(|value| STANDARD.decode(value).ok())
            .map(Into::into),
        speech_recognized_pinyin: input.speech_recognized_pinyin,
    };
    crate::db::practice_records::insert(&db, &record, &student.id, class_id.as_deref()).await?;
    Response::from_json(&serde_json::json!({"ok":true,"classId":class_id}))
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ClassRecordPage {
    offset: Option<u32>,
    limit: Option<u32>,
    before_time: Option<String>,
    after_id: Option<String>,
    snapshot_row_id: Option<i64>,
}

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct StudentRecordPage {
    limit: Option<u32>,
    before_time: Option<String>,
    after_id: Option<String>,
}

pub(super) async fn student_records(request: &Request, env: &Env) -> Result<Response> {
    let Some(student) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if student.role != "student" {
        return error("forbidden", 403);
    }
    let page = match request.query::<StudentRecordPage>() {
        Ok(page) => page,
        Err(_) => return error("invalid pagination", 400),
    };
    if page.before_time.is_some() != page.after_id.is_some()
        || page
            .before_time
            .as_ref()
            .is_some_and(|v| v.is_empty() || v.len() > 40)
        || page
            .after_id
            .as_ref()
            .is_some_and(|v| v.len() != 32 || !v.bytes().all(|b| b.is_ascii_hexdigit()))
    {
        return error("invalid cursor", 400);
    }
    let limit = page.limit.unwrap_or(100).clamp(1, 500);
    let db = env.d1("DB")?;
    let mut records = crate::db::practice_records::list_for_student_page(
        &db,
        &student.id,
        limit + 1,
        page.before_time.as_deref(),
        page.after_id.as_deref(),
    )
    .await?;
    let has_more = records.len() > limit as usize;
    records.truncate(limit as usize);
    let next_cursor = if has_more {
        records
            .last()
            .map(|r| serde_json::json!({"beforeTime":r.occurred_at,"afterId":r.id}))
    } else {
        None
    };
    Response::from_json(&serde_json::json!({"records":records,"nextCursor":next_cursor}))
}

pub(super) async fn class_records(
    request: &Request,
    env: &Env,
    class_id: &str,
) -> Result<Response> {
    let Some(admin) = current_account(request, env).await? else {
        return error("unauthorized", 401);
    };
    if admin.role != "class_admin" {
        return error("forbidden", 403);
    }
    let db = env.d1("DB")?;
    if !crate::db::classes::exists_for_admin(&db, class_id, &admin.id).await? {
        return error("class not found", 404);
    }
    let page = match request.query::<ClassRecordPage>() {
        Ok(page) => page,
        Err(_) => return error("invalid pagination", 400),
    };
    let limit = page.limit.unwrap_or(100).clamp(1, 500);
    let has_cursor =
        page.before_time.is_some() || page.after_id.is_some() || page.snapshot_row_id.is_some();
    if page.before_time.is_some() != page.after_id.is_some()
        || page.snapshot_row_id.is_some() != page.before_time.is_some()
        || page
            .before_time
            .as_ref()
            .is_some_and(|value| value.is_empty() || value.len() > 40)
        || page.after_id.as_ref().is_some_and(|value| {
            value.len() != 32 || !value.bytes().all(|byte| byte.is_ascii_hexdigit())
        })
        || page.snapshot_row_id.is_some_and(|value| value <= 0)
    {
        return error("invalid cursor", 400);
    }
    if has_cursor && page.offset.is_some() {
        return error("cannot mix cursor and offset pagination", 400);
    }
    if page.offset.is_some() {
        let offset = page.offset.unwrap_or(0);
        let records =
            crate::db::practice_records::list_for_class_offset_page(&db, class_id, limit, offset)
                .await?;
        return Response::from_json(&serde_json::json!({
            "records":records,"offset":offset,"limit":limit
        }));
    }
    let snapshot_row_id = page
        .snapshot_row_id
        .unwrap_or(crate::db::practice_records::class_snapshot_row_id(&db, class_id).await?);
    let mut records = crate::db::practice_records::list_for_class_cursor_page(
        &db,
        class_id,
        snapshot_row_id,
        page.before_time.as_deref(),
        page.after_id.as_deref(),
        limit + 1,
    )
    .await?;
    let has_more = records.len() > limit as usize;
    records.truncate(limit as usize);
    let next_cursor = if has_more {
        records.last().map(|record| {
            serde_json::json!({
                "beforeTime":record.occurred_at,
                "afterId":record.id,
                "snapshotRowId":snapshot_row_id
            })
        })
    } else {
        None
    };
    Response::from_json(&serde_json::json!({
        "records":records,
        "nextCursor":next_cursor,
        "snapshotRowId":snapshot_row_id,
        "limit":limit
    }))
}

fn valid_input(input: &PracticeRecordInput) -> bool {
    let timestamp_is_valid = valid_timestamp(&input.occurred_at);
    let id_is_hex = input.id.len() == 32 && input.id.bytes().all(|byte| byte.is_ascii_hexdigit());
    let valid_text =
        |value: &str, max: usize| !value.trim().is_empty() && value.chars().count() <= max;
    let original_answer_is_valid = match (
        &input.handwriting_gzip,
        &input.ocr_results,
        &input.review_bits,
    ) {
        (None, None, None) => {
            input.direction == "readAloud"
                && input
                    .speech_snac
                    .as_deref()
                    .and_then(decode_valid_snac)
                    .is_some()
                && input
                    .speech_recognized_pinyin
                    .as_ref()
                    .is_some_and(|value| value.len() <= 4000)
                && input.speech_review_bits.as_ref().is_some_and(|bits| {
                    let count = input
                        .expected_answer
                        .chars()
                        .filter(|ch| ('\u{3400}'..='\u{9fff}').contains(ch))
                        .count();
                    count > 0 && valid_review_bits(bits, count, input.is_correct)
                })
        }
        (Some(handwriting), Some(ocr), Some(review_bits)) => {
            let cell_count = handwriting_cell_count(handwriting);
            input.direction != "readAloud"
                && input.speech_snac.is_none()
                && input.speech_review_bits.is_none()
                && input.speech_recognized_pinyin.is_none()
                && cell_count.is_some_and(|count| {
                    ocr.len() == count && valid_review_bits(review_bits, count, input.is_correct)
                })
                && ocr.iter().all(|value| value.chars().count() <= 256)
        }
        _ => false,
    };
    id_is_hex
        && valid_text(&input.textbook_key, 128)
        && valid_text(&input.question_id, 256)
        && valid_text(&input.chapter_id, 128)
        && valid_text(&input.question_kind, 64)
        && valid_text(&input.category, 64)
        && valid_text(&input.source, 256)
        && valid_text(&input.prompt, 2000)
        && valid_text(&input.student_answer, 2000)
        && valid_text(&input.expected_answer, 2000)
        && valid_text(&input.occurred_at, 40)
        && timestamp_is_valid
        && original_answer_is_valid
        && matches!(
            input.direction.as_str(),
            "writeHanzi" | "writePinyin" | "listenWriteHanzi" | "readAloud"
        )
}

fn decode_valid_snac(value: &str) -> Option<Vec<u8>> {
    if value.len() > 64 * 1024 {
        return None;
    }
    let bytes = STANDARD.decode(value).ok()?;
    if bytes.len() < 60
        || bytes.len() > 48 * 1024
        || &bytes[..8] != b"SNACLB01"
        || u16::from_le_bytes([bytes[8], bytes[9]]) != 1
        || u16::from_le_bytes([bytes[10], bytes[11]]) != 3
        || u32::from_le_bytes(bytes[12..16].try_into().ok()?) != 24000
        || u32::from_le_bytes(bytes[16..20].try_into().ok()?) != 4096
    {
        return None;
    }
    let samples = u64::from_le_bytes(bytes[20..28].try_into().ok()?);
    if samples == 0 || samples > 120 * 24000 {
        return None;
    }
    let mut offset = 28usize;
    for _ in 0..3 {
        let count = u32::from_le_bytes(bytes.get(offset..offset + 4)?.try_into().ok()?) as usize;
        let length =
            u32::from_le_bytes(bytes.get(offset + 4..offset + 8)?.try_into().ok()?) as usize;
        if count == 0 || length != count.saturating_mul(12).div_ceil(8) {
            return None;
        }
        offset = offset.checked_add(8 + length)?;
        if offset > bytes.len() - 4 {
            return None;
        }
    }
    if offset != bytes.len() - 4 {
        return None;
    }
    let expected_crc = u32::from_le_bytes(bytes[offset..].try_into().ok()?);
    let actual_crc = crc32fast::hash(&bytes[..offset]);
    (expected_crc == actual_crc).then_some(bytes)
}

#[cfg(target_arch = "wasm32")]
fn valid_timestamp(value: &str) -> bool {
    let occurred_at_ms = js_sys::Date::parse(value);
    occurred_at_ms.is_finite() && occurred_at_ms <= js_sys::Date::now() + 5.0 * 60.0 * 1000.0
}

#[cfg(not(target_arch = "wasm32"))]
fn valid_timestamp(value: &str) -> bool {
    // Host-only unit tests cannot invoke js_sys::Date. Production uses the
    // wasm32 implementation above; keep the host check limited to ISO shape.
    value.contains('T') && value.ends_with('Z')
}

fn handwriting_cell_count(value: &str) -> Option<usize> {
    let compressed = decode_valid_handwriting(value)?;
    let mut decoder = GzDecoder::new(compressed.as_slice()).take(256 * 1024 + 1);
    let mut decoded = Vec::new();
    decoder.read_to_end(&mut decoded).ok()?;
    serde_json::from_slice::<serde_json::Value>(&decoded)
        .ok()?
        .get("cells")?
        .as_array()
        .map(Vec::len)
}

fn valid_review_bits(value: &str, cell_count: usize, is_correct: bool) -> bool {
    let Ok(bytes) = STANDARD.decode(value) else {
        return false;
    };
    if bytes.len() != cell_count.div_ceil(8) {
        return false;
    }
    let bit = |index: usize| bytes[index / 8] & (1 << (index % 8)) != 0;
    let unused_bits_are_zero = (cell_count..bytes.len() * 8).all(|index| !bit(index));
    unused_bits_are_zero && (0..cell_count).all(bit) == is_correct
}

fn decode_valid_handwriting(value: &str) -> Option<Vec<u8>> {
    if value.len() > 96 * 1024 {
        return None;
    }
    let compressed = STANDARD.decode(value).ok()?;
    let mut decoder = GzDecoder::new(compressed.as_slice()).take(256 * 1024 + 1);
    let mut decoded = Vec::new();
    if decoder.read_to_end(&mut decoded).is_err() || decoded.len() > 256 * 1024 {
        return None;
    }
    let document = serde_json::from_slice::<serde_json::Value>(&decoded).ok()?;
    let valid = document.get("version").and_then(|value| value.as_u64()) == Some(1)
        && document.get("coordinates").and_then(|value| value.as_str()) == Some("cell-relative")
        && document
            .get("brushWidthUnit")
            .and_then(|value| value.as_str())
            == Some("cell-height")
        && valid_ink_cells(document.get("cells"));
    valid.then_some(compressed)
}

fn valid_ink_cells(value: Option<&serde_json::Value>) -> bool {
    let Some(cells) = value.and_then(|value| value.as_array()) else {
        return false;
    };
    if cells.is_empty() || cells.len() > 100 {
        return false;
    }
    let mut total_points = 0usize;
    cells.iter().all(|cell| {
        let Some(cell) = cell.as_object() else {
            return false;
        };
        let valid_size = ["width", "height"].iter().all(|key| {
            cell.get(*key)
                .and_then(|value| value.as_f64())
                .is_some_and(|value| value.is_finite() && value > 0.0 && value <= 2_000.0)
        });
        let valid_grid = cell
            .get("grid")
            .and_then(|value| value.as_str())
            .is_some_and(|value| matches!(value, "hanzi" | "pinyin"));
        let Some(strokes) = cell.get("strokes").and_then(|value| value.as_array()) else {
            return false;
        };
        valid_size
            && valid_grid
            && strokes.len() <= 500
            && strokes.iter().all(|stroke| {
                let Some(stroke) = stroke.as_object() else {
                    return false;
                };
                let valid_color = stroke
                    .get("color")
                    .and_then(|value| value.as_u64())
                    .is_some_and(|value| value <= u32::MAX as u64);
                let valid_width = stroke
                    .get("width")
                    .and_then(|value| value.as_f64())
                    .is_some_and(|value| value.is_finite() && value > 0.0 && value <= 1.0);
                let Some(points) = stroke.get("points").and_then(|value| value.as_array()) else {
                    return false;
                };
                total_points += points.len();
                valid_color
                    && valid_width
                    && total_points <= 100_000
                    && points.iter().all(|point| {
                        point.as_array().is_some_and(|coordinates| {
                            coordinates.len() == 2
                                && coordinates.iter().all(|coordinate| {
                                    coordinate.as_f64().is_some_and(|coordinate| {
                                        coordinate.is_finite() && coordinate.abs() <= 10.0
                                    })
                                })
                        })
                    })
            })
    })
}

#[cfg(test)]
mod tests {
    use super::{valid_input, PracticeRecordInput};
    use base64::{engine::general_purpose::STANDARD, Engine};
    use flate2::{write::GzEncoder, Compression};
    use std::io::Write;

    fn snac_fixture() -> String {
        let mut bytes = b"SNACLB01".to_vec();
        bytes.extend_from_slice(&1u16.to_le_bytes());
        bytes.extend_from_slice(&3u16.to_le_bytes());
        bytes.extend_from_slice(&24000u32.to_le_bytes());
        bytes.extend_from_slice(&4096u32.to_le_bytes());
        bytes.extend_from_slice(&24000u64.to_le_bytes());
        for _ in 0..3 {
            bytes.extend_from_slice(&1u32.to_le_bytes());
            bytes.extend_from_slice(&2u32.to_le_bytes());
            bytes.extend_from_slice(&[0, 0]);
        }
        let crc = crc32fast::hash(&bytes);
        bytes.extend_from_slice(&crc.to_le_bytes());
        STANDARD.encode(bytes)
    }

    fn input() -> PracticeRecordInput {
        PracticeRecordInput {
            id: "0123456789abcdef0123456789abcdef".into(),
            textbook_key: "grade2b.json".into(),
            question_id: "poem:test".into(),
            chapter_id: "chapter-1".into(),
            question_kind: "诗词".into(),
            category: "诗词".into(),
            source: "静夜思".into(),
            direction: "readAloud".into(),
            prompt: "chuáng qián míng yuè guāng".into(),
            student_answer: "床前明月光".into(),
            expected_answer: "床前明月光".into(),
            is_correct: true,
            occurred_at: "2026-10-13T01:23:45.000Z".into(),
            handwriting_gzip: None,
            ocr_results: None,
            review_bits: None,
            speech_snac: Some(snac_fixture()),
            speech_review_bits: Some(STANDARD.encode([0b00011111])),
            speech_recognized_pinyin: Some("chuáng qián míng yuè guāng".into()),
        }
    }

    #[test]
    fn accepts_valid_practice_attempt() {
        assert!(valid_input(&input()));
    }

    #[test]
    fn rejects_bad_id_or_direction() {
        let mut record = input();
        record.id = "not-an-id".into();
        assert!(!valid_input(&record));

        let mut record = input();
        record.direction = "admin".into();
        assert!(!valid_input(&record));
    }

    #[test]
    fn reading_requires_valid_audio_and_per_character_review() {
        let mut record = input();
        assert!(valid_input(&record));
        record.speech_snac = None;
        assert!(!valid_input(&record));
        record.speech_snac = Some(STANDARD.encode(b"not snac"));
        assert!(!valid_input(&record));
        record.speech_snac = Some(snac_fixture());
        record.speech_review_bits = Some(STANDARD.encode([0b11111111]));
        assert!(!valid_input(&record));
        record.speech_review_bits = Some(STANDARD.encode([0b00011110]));
        assert!(!valid_input(&record));
        record.is_correct = false;
        assert!(valid_input(&record));
    }

    #[test]
    fn accepts_valid_original_handwriting_and_rejects_partial_or_plain_data() {
        let document = br#"{"version":1,"coordinates":"cell-relative","brushWidthUnit":"cell-height","layout":"ordered-wrap","spacing":12,"cells":[{"grid":"hanzi","width":72,"height":72,"strokes":[{"color":4278190080,"width":0.05,"points":[[0.1,0.2],[0.8,0.9]]}]}]}"#;
        let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
        encoder.write_all(document).unwrap();
        let compressed = STANDARD.encode(encoder.finish().unwrap());

        let mut record = input();
        record.direction = "writeHanzi".into();
        record.speech_snac = None;
        record.speech_review_bits = None;
        record.speech_recognized_pinyin = None;
        record.handwriting_gzip = Some(compressed);
        record.ocr_results = Some(vec!["春".into()]);
        record.review_bits = Some(STANDARD.encode([1]));
        assert!(valid_input(&record));

        record.ocr_results = None;
        assert!(!valid_input(&record));
        record.ocr_results = Some(vec!["春".into()]);
        record.review_bits = None;
        assert!(!valid_input(&record));
        record.review_bits = Some(STANDARD.encode([1]));
        record.handwriting_gzip = Some(STANDARD.encode(document));
        assert!(!valid_input(&record));
        record.direction = "readAloud".into();
        assert!(!valid_input(&record));
    }
}
