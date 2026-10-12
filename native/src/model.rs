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
}
