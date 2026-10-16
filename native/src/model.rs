//! What the window says about the logins: the same lanes, best hop and headline as the HTML
//! window (DashboardScriptOverview), so both read the situation the same way.

use crate::api::{Account, Limit, Tool};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Lane {
    Needs,
    Active,
    Hot,
    Room,
    Quiet,
}

/// Seconds since 1970 from `2026-10-12T17:23:51Z`; nil for anything else.
pub fn epoch(iso: &str) -> Option<i64> {
    let b = iso.as_bytes();
    if b.len() < 19 {
        return None;
    }
    let n = |r: std::ops::Range<usize>| iso.get(r)?.parse::<i64>().ok();
    let (y, m, d) = (n(0..4)?, n(5..7)?, n(8..10)?);
    let (hh, mm, ss) = (n(11..13)?, n(14..16)?, n(17..19)?);
    // Days from the civil calendar (Howard Hinnant's algorithm).
    let y = if m <= 2 { y - 1 } else { y };
    let era = if y >= 0 { y } else { y - 399 } / 400;
    let yoe = y - era * 400;
    let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    let days = era * 146_097 + doe - 719_468;
    Some(days * 86_400 + hh * 3_600 + mm * 60 + ss)
}

pub fn now() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs() as i64).unwrap_or(0)
}

pub fn max_used(account: &Account) -> f64 {
    account.limits.iter().map(|l| l.used_percent).fold(0.0, f64::max)
}

pub fn tightest(account: &Account) -> Option<&Limit> {
    account.limits.iter().max_by(|a, b| a.used_percent.total_cmp(&b.used_percent))
}

fn runs_out_soon(limit: &Limit) -> bool {
    let Some(eta) = limit.runs_out_at.as_deref().and_then(epoch) else { return false };
    if eta <= now() {
        return false;
    }
    !matches!(limit.resets_at.as_deref().and_then(epoch), Some(reset) if eta >= reset)
}

pub fn lane(account: &Account) -> Lane {
    if account.error.is_some() {
        return Lane::Needs;
    }
    if account.limits.is_empty() {
        return Lane::Quiet;
    }
    let used = max_used(account);
    if used >= 85.0 || account.limits.iter().any(runs_out_soon) {
        return Lane::Needs;
    }
    if account.active {
        return Lane::Active;
    }
    if used >= 60.0 { Lane::Hot } else { Lane::Room }
}

/// The login with the most room for a tool, if it has fifteen points more than the one in use.
pub fn alternative<'a>(tool: &'a Tool, current: Option<&Account>) -> Option<&'a Account> {
    let pick = tool
        .accounts
        .iter()
        .filter(|a| !a.active && !a.limits.is_empty())
        .min_by(|a, b| max_used(a).total_cmp(&max_used(b)))?;
    match current {
        Some(current) if max_used(pick) + 15.0 >= max_used(current) => None,
        _ => Some(pick),
    }
}

pub struct Hop<'a> {
    pub tool: &'a Tool,
    pub from: &'a Account,
    pub to: &'a Account,
}

pub fn best_hop(tools: &[Tool]) -> Option<Hop<'_>> {
    let mut best: Option<(f64, Hop)> = None;
    for tool in tools {
        let Some(active) = tool.accounts.iter().find(|a| a.active) else { continue };
        let Some(to) = alternative(tool, Some(active)) else { continue };
        let gap = max_used(active) - max_used(to);
        if best.as_ref().is_none_or(|(g, _)| gap > *g) {
            best = Some((gap, Hop { tool, from: active, to }));
        }
    }
    best.map(|(_, hop)| hop)
}

pub struct Headline {
    pub title: String,
    pub sub: String,
    pub note: String,
    pub target: Option<String>,
}

pub fn headline(tools: &[Tool]) -> Headline {
    let stuck = tools.iter().flat_map(|t| t.accounts.iter().map(move |a| (t, a))).find(|(t, a)| {
        a.error.is_none() && lane(a) == Lane::Needs && alternative(t, Some(a)).is_none()
    });
    if let Some(hop) = best_hop(tools) {
        return Headline {
            title: format!("{} still has room.", hop.to.name),
            sub: format!(
                "{} {} is in use at {:.0}%. {} is at {:.0}%.",
                hop.tool.name, hop.from.name, max_used(hop.from), hop.to.name, max_used(hop.to)
            ),
            note: stuck
                .map(|(t, a)| format!("{} is at {:.0}% and has no other login.", t.name, max_used(a)))
                .unwrap_or_default(),
            target: Some(hop.to.id.clone()),
        };
    }
    if let Some((tool, account)) = stuck {
        return Headline {
            title: format!("{} is at {:.0}%.", tool.name, max_used(account)),
            sub: "There is no other login to hop to.".into(),
            note: String::new(),
            target: None,
        };
    }
    Headline {
        title: "Every login in use has room.".into(),
        sub: "Nothing is close to a limit.".into(),
        note: String::new(),
        target: None,
    }
}

pub fn window_name(label: &str) -> String {
    match label {
        "5h" => "5-hour".into(),
        "Week" => "Weekly".into(),
        "Opus" => "Opus weekly".into(),
        "Sonnet" => "Sonnet weekly".into(),
        other => other.into(),
    }
}

pub fn tokens(value: u64) -> String {
    let v = value as f64;
    let trim = |x: f64, suffix: &str| {
        let text = if x >= 100.0 { format!("{x:.0}") } else { format!("{x:.1}") };
        format!("{}{suffix}", text.trim_end_matches(".0"))
    };
    if v >= 1e9 {
        trim(v / 1e9, "B")
    } else if v >= 1e6 {
        trim(v / 1e6, "M")
    } else if v >= 1e3 {
        trim(v / 1e3, "K")
    } else {
        value.to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn account(id: &str, active: bool, used: f64) -> Account {
        Account {
            id: id.into(),
            name: id.into(),
            active,
            limits: vec![Limit { label: "5h".into(), used_percent: used, ..Default::default() }],
            ..Default::default()
        }
    }

    #[test]
    fn epoch_reads_utc() {
        assert_eq!(epoch("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(epoch("2026-10-12T17:23:51Z"), Some(1_791_825_831));
        assert_eq!(epoch("nonsense"), None);
    }

    #[test]
    fn lanes_and_the_best_hop_match_the_html_window() {
        assert_eq!(lane(&account("a", true, 90.0)), Lane::Needs);
        assert_eq!(lane(&account("a", true, 40.0)), Lane::Active);
        assert_eq!(lane(&account("a", false, 70.0)), Lane::Hot);
        assert_eq!(lane(&account("a", false, 10.0)), Lane::Room);
        let tool = Tool { id: "claude".into(), name: "Claude Code".into(), accounts: vec![account("work", true, 80.0), account("home", false, 20.0)] };
        let tools = vec![tool];
        let hop = best_hop(&tools).expect("a hop");
        assert_eq!(hop.to.id, "home");
        assert_eq!(headline(&tools).title, "home still has room.");
        // Ten points is not enough room to hop.
        let close = vec![Tool { id: "c".into(), name: "C".into(), accounts: vec![account("a", true, 50.0), account("b", false, 41.0)] }];
        assert!(best_hop(&close).is_none());
    }

    #[test]
    fn tokens_read_like_the_window() {
        assert_eq!(tokens(999), "999");
        assert_eq!(tokens(7_935_127), "7.9M");
        assert_eq!(tokens(120_000_000), "120M");
        assert_eq!(tokens(1_000_000), "1M");
    }

    #[test]
    fn columns_fold_measured_then_projected() {
        let quota = crate::api::Quota { step: 1800, past_start: "2026-10-12T10:00:00Z".into(), forecast_start: "2026-10-12T12:00:00Z".into(), ..Default::default() };
        let pool = crate::api::Pool { capacity: 200.0, past: vec![Some(150.0), None, Some(140.0), Some(130.0), Some(120.0)], forecast: vec![120.0, 110.0, 100.0, 190.0], ..Default::default() };
        let from = epoch("2026-10-12T10:00:00Z").unwrap();
        let cols = columns(&quota, &pool, from, from + 4 * 3600, 4);
        assert_eq!(cols[0], Some((150.0, true)));
        assert_eq!(cols[1], Some((130.0, true)));
        assert_eq!(cols[2], Some((110.0, false)));
        assert_eq!(cols[3], Some((190.0, false)));
        assert_eq!(per_hour(3.25), "3.2% an hour");
        assert_eq!(per_hour(44.0), "44% an hour");
    }
}

/// How long until a moment, the way the window says it: "2d 7h", "3h 5m", "12m".
pub fn until(iso: &str) -> String {
    let Some(at) = epoch(iso) else { return String::new() };
    let s = (at - now()).max(0);
    let (d, h, m) = (s / 86_400, (s % 86_400) / 3_600, (s % 3_600) / 60);
    if d > 0 {
        format!("{d}d {h}h")
    } else if h > 0 {
        format!("{h}h {m}m")
    } else {
        format!("{}m", m.max(1))
    }
}

/// A drain rate in percent an hour, to one decimal under ten.
pub fn per_hour(rate: f64) -> String {
    if rate >= 10.0 { format!("{rate:.0}% an hour") } else { format!("{rate:.1}% an hour") }
}

/// A pool's remaining share over time, folded into `count` columns from `from` to `to` (seconds):
/// each column the last value known in it, and whether it was measured or projected.
pub fn columns(quota: &crate::api::Quota, pool: &crate::api::Pool, from: i64, to: i64, count: usize) -> Vec<Option<(f64, bool)>> {
    let step = quota.step.max(60);
    let past0 = epoch(&quota.past_start).unwrap_or(0);
    let ahead0 = epoch(&quota.forecast_start).unwrap_or(0);
    let mut points: Vec<(i64, f64, bool)> = pool.past.iter().enumerate().filter_map(|(i, v)| v.map(|v| (past0 + i as i64 * step, v, true))).collect();
    points.extend(pool.forecast.iter().enumerate().skip(1).map(|(i, v)| (ahead0 + i as i64 * step, *v, false)));
    let width = ((to - from) as f64 / count as f64).max(1.0);
    (0..count)
        .map(|c| {
            let start = from + (c as f64 * width) as i64;
            let end = from + ((c + 1) as f64 * width) as i64;
            points.iter().filter(|(t, _, _)| *t >= start && *t < end).last().map(|(_, v, measured)| (*v, *measured))
        })
        .collect()
}

/// Home's tools share one blue, lightest for the largest share (KB-Home).
pub const SHARE_BLUES: [u32; 6] = [0xa8cefc, 0x80b7fb, 0x60a5fa, 0x4d84c8, 0x3d6aa0, 0x2e4f78];

/// The pet's stages and the lifetime tokens each starts at.
pub const PET_STAGES: [(&str, &str, u64); 6] = [
    ("speck", "Speck", 0),
    ("hatch", "Hatch", 1_000_000),
    ("frame", "Frame", 50_000_000),
    ("bulk", "Bulk", 500_000_000),
    ("mass", "Mass", 5_000_000_000),
    ("monument", "Monument", 25_000_000_000),
];

/// Where the pet is between its stage and the next: 0 at the stage's start, 1 at the next one.
pub fn stage_progress(pet: &crate::api::Pet) -> (usize, f32) {
    let at = PET_STAGES.iter().position(|(id, _, _)| *id == pet.stage).unwrap_or(0);
    let Some(next) = &pet.next else { return (at, 1.0) };
    let from = PET_STAGES[at].2 as f64;
    let to = (pet.tokens + next.tokens) as f64;
    let share = if to > from { (pet.tokens as f64 - from) / (to - from) } else { 1.0 };
    (at, share.clamp(0.0, 1.0) as f32)
}

/// One bar of Tokens per day: its day, its tokens, and whether it is from the span before the range.
#[derive(Clone, Debug, PartialEq)]
pub struct DayBar {
    pub day: String,
    pub tokens: u64,
    pub before: bool,
}

/// The range's steps, summed over every series; a week also brings the 7 days before it, dimmed.
pub fn trend(usage: &crate::api::Usage, week: bool) -> Vec<DayBar> {
    let mut bars: Vec<DayBar> = usage
        .buckets
        .iter()
        .map(|b| DayBar { day: b.start.get(0..10).unwrap_or_default().to_string(), tokens: b.values.values().map(|v| v.tokens).sum(), before: false })
        .collect();
    if week {
        let first = usage.start.get(0..10).unwrap_or_default();
        if let Some(at) = usage.heatmap.iter().position(|d| d.day == first) {
            let before: Vec<DayBar> = usage.heatmap[at.saturating_sub(7)..at].iter().map(|d| DayBar { day: d.day.clone(), tokens: d.tokens, before: true }).collect();
            bars.splice(0..0, before);
        }
    }
    bars
}

/// The heatmap's level for each day: 0 for none, 1–4 by quartile of the active days.
pub fn heat_levels(days: &[crate::api::HeatDay]) -> Vec<u8> {
    let mut active: Vec<u64> = days.iter().map(|d| d.tokens).filter(|&t| t > 0).collect();
    active.sort_unstable();
    let q = |x: f64| active.get(((x * active.len() as f64) as usize).min(active.len().saturating_sub(1))).copied().unwrap_or(0);
    let cuts = [q(0.25), q(0.5), q(0.75)];
    days.iter()
        .map(|d| match d.tokens {
            0 => 0,
            t if t <= cuts[0] => 1,
            t if t <= cuts[1] => 2,
            t if t <= cuts[2] => 3,
            _ => 4,
        })
        .collect()
}

/// A count with thousands separators: 44,958,228.
pub fn count(value: u64) -> String {
    let digits = value.to_string();
    let mut out = String::new();
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i) % 3 == 0 {
            out.push(',');
        }
        out.push(c);
    }
    out
}

/// "#F3EAD8" as a colour value.
pub fn hex(color: &str) -> u32 {
    u32::from_str_radix(color.trim_start_matches('#').get(0..6).unwrap_or("ffffff"), 16).unwrap_or(0xffffff)
}

/// How long ago, the way the window says it: "2m ago".
pub fn ago(iso: &str) -> String {
    let Some(at) = epoch(iso) else { return String::new() };
    let s = (now() - at).max(0);
    match s {
        0..60 => "just now".into(),
        60..3_600 => format!("{}m ago", s / 60),
        3_600..86_400 => format!("{}h ago", s / 3_600),
        _ => format!("{}d ago", s / 86_400),
    }
}

/// A day ("2026-10-13") as the axis says it: "Oct 13".
pub fn short_day(day: &str) -> String {
    const MONTHS: [&str; 12] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    let month = day.get(5..7).and_then(|m| m.parse::<usize>().ok()).unwrap_or(1);
    let date = day.get(8..10).and_then(|d| d.parse::<u32>().ok()).unwrap_or(1);
    format!("{} {date}", MONTHS[(month.max(1) - 1).min(11)])
}

#[cfg(test)]
mod home_tests {
    use super::*;
    use crate::api::{Bucket, BucketValue, HeatDay, Pet, PetNext, Usage};

    #[test]
    fn the_pet_sits_between_its_stage_and_the_next() {
        let pet = Pet { stage: "bulk".into(), tokens: 800_000_000, next: Some(PetNext { label: "Mass".into(), tokens: 4_200_000_000 }), ..Default::default() };
        let (at, share) = stage_progress(&pet);
        assert_eq!(at, 3);
        assert!((share - 0.0667).abs() < 0.001);
    }

    #[test]
    fn a_week_brings_the_seven_days_before_it() {
        let heatmap: Vec<HeatDay> = (1..=14).map(|d| HeatDay { day: format!("2026-10-{d:02}"), tokens: d }).collect();
        let buckets = (8..=14).map(|d| Bucket { start: format!("2026-10-{d:02}T00:00:00Z"), values: [("a".to_string(), BucketValue { tokens: d * 10 })].into() }).collect();
        let usage = Usage { start: "2026-10-08T00:00:00Z".into(), heatmap, buckets, ..Default::default() };
        let bars = trend(&usage, true);
        assert_eq!(bars.len(), 14);
        assert!(bars[0].before && bars[0].tokens == 1);
        assert!(!bars[13].before && bars[13].tokens == 140);
    }

    #[test]
    fn counts_levels_and_days_read_like_the_window() {
        assert_eq!(count(44_958_228), "44,958,228");
        assert_eq!(count(999), "999");
        let days: Vec<HeatDay> = [0, 1, 2, 3, 4].iter().map(|&t| HeatDay { day: String::new(), tokens: t }).collect();
        // The same cuts as the HTML window: the quartiles of the active days, taken by index.
        assert_eq!(heat_levels(&days), vec![0, 1, 1, 2, 3]);
        assert_eq!(hex("#F3EAD8"), 0xf3ead8);
        assert_eq!(short_day("2026-10-13"), "Oct 13");
    }
}
