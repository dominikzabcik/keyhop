//! Keyhop's window in GPUI, after the KB boards: the sidebar with each limit live, Home (the
//! total, tokens per day, top models, the pet's night, activity and what needs you) and Limits
//! (what the logins have left and how it went, measured only), drawn over the same local API the
//! HTML window reads. The top bar carries the field switch and what is being read; there is no
//! status bar.

use crate::api::{Account, Client, Pet, Pool, Quota, State, Tool, Usage};
use crate::model::{self, Lane};
use crate::theme::Theme;
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::*;
use std::collections::HashMap;
use std::time::Duration;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Section {
    Home,
    Limits,
}

/// Home's ranges, as the API names them and as the tabs say them.
const RANGES: [(&str, &str); 4] = [("today", "Day"), ("week", "Week"), ("month", "Month"), ("all", "All")];

pub struct KeyhopWindow {
    client: Client,
    state: Option<State>,
    quota: Option<Quota>,
    usage: HashMap<String, Usage>,
    pet: Option<Pet>,
    /// Today as the top bar says it: "Friday, October 16".
    today: String,
    range: &'static str,
    /// The suggestion the pet was told to keep quiet about.
    later: Option<String>,
    /// The tool Limits is narrowed to, or "all".
    quota_tool: String,
    /// How far back Limits' history reaches: 24 or 168 hours.
    quota_hours: i64,
    problem: Option<String>,
    toast: Option<String>,
    section: Section,
    theme: Theme,
    busy: bool,
}

/// Everything one read brings back, gathered off the main thread.
struct Loaded {
    state: anyhow::Result<State>,
    quota: Option<Quota>,
    usage: Vec<(String, Usage)>,
    pet: Option<Pet>,
    today: String,
}

fn fetch(client: &Client, range: &str) -> Loaded {
    let state = client.state();
    let quota = client.quota().ok();
    let mut usage = Vec::new();
    for wanted in if range == "week" { vec!["week"] } else { vec![range, "week"] } {
        if let Ok(doc) = client.usage(wanted) {
            usage.push((wanted.to_string(), doc));
        }
    }
    let linked = state.as_ref().is_ok_and(|s| s.cloud.linked);
    let pet = if linked { client.pet().ok() } else { None };
    let today = std::process::Command::new("date")
        .arg("+%A, %B %-d")
        .output()
        .ok()
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .unwrap_or_default();
    Loaded { state, quota, usage, pet, today }
}

impl KeyhopWindow {
    pub fn new(client: Client, section: Section, cx: &mut Context<Self>) -> Self {
        let window = Self {
            client,
            state: None,
            quota: None,
            usage: HashMap::new(),
            pet: None,
            today: String::new(),
            range: "week",
            later: None,
            quota_tool: "all".into(),
            quota_hours: 24,
            problem: None,
            toast: None,
            section,
            theme: Theme::world(),
            busy: false,
        };
        // Read everything now and every twenty seconds, off the main thread.
        cx.spawn(async move |this, cx| {
            loop {
                let Ok((client, range)) = this.read_with(cx, |this, _| (this.client.clone(), this.range)) else { break };
                let loaded = cx.background_executor().spawn(async move { fetch(&client, range) }).await;
                if this
                    .update(cx, |this, cx| {
                        this.take(loaded);
                        cx.notify();
                    })
                    .is_err()
                {
                    break;
                }
                cx.background_executor().timer(Duration::from_secs(20)).await;
            }
        })
        .detach();
        window
    }

    fn take(&mut self, loaded: Loaded) {
        if loaded.quota.is_some() {
            self.quota = loaded.quota;
        }
        for (range, doc) in loaded.usage {
            self.usage.insert(range, doc);
        }
        if loaded.pet.is_some() {
            self.pet = loaded.pet;
        }
        if !loaded.today.is_empty() {
            self.today = loaded.today;
        }
        match loaded.state {
            Ok(state) => {
                self.state = Some(state);
                self.problem = None;
            }
            Err(error) => self.problem = Some(error.to_string()),
        }
    }

    fn reload(&mut self, cx: &mut Context<Self>) {
        let client = self.client.clone();
        let range = self.range;
        cx.spawn(async move |this, cx| {
            let loaded = cx.background_executor().spawn(async move { fetch(&client, range) }).await;
            let _ = this.update(cx, |this, cx| {
                this.take(loaded);
                cx.notify();
            });
        })
        .detach();
    }

    fn hop(&mut self, account: String, cx: &mut Context<Self>) {
        if self.busy {
            return;
        }
        self.busy = true;
        self.toast = Some("Hopping…".into());
        cx.notify();
        let client = self.client.clone();
        cx.spawn(async move |this, cx| {
            let result = cx.background_executor().spawn(async move { client.switch(&account) }).await;
            let _ = this.update(cx, |this, cx| {
                this.busy = false;
                this.toast = Some(match result {
                    Ok(message) => message,
                    Err(error) => error.to_string(),
                });
                this.reload(cx);
                cx.notify();
            });
        })
        .detach();
    }

    fn refresh(&mut self, cx: &mut Context<Self>) {
        self.toast = Some("Reading limits…".into());
        cx.notify();
        let client = self.client.clone();
        cx.spawn(async move |this, cx| {
            let _ = cx.background_executor().spawn(async move { client.refresh() }).await;
            let _ = this.update(cx, |this, cx| {
                this.toast = None;
                this.reload(cx);
            });
        })
        .detach();
    }

    /// The places this window doesn't draw yet open in the HTML window, which has them all.
    fn open_page(&mut self, section: &str, cx: &mut Context<Self>) {
        let url = self.client.page(section);
        let opener = if cfg!(target_os = "macos") { "open" } else { "xdg-open" };
        self.toast = Some(match std::process::Command::new(opener).arg(&url).spawn() {
            Ok(_) => "Opened in Keyhop's window.".into(),
            Err(_) => format!("Open {url}"),
        });
        cx.notify();
    }

    fn set_range(&mut self, range: &'static str, cx: &mut Context<Self>) {
        self.range = range;
        cx.notify();
        if !self.usage.contains_key(range) {
            self.reload(cx);
        }
    }

    // MARK: Pieces

    /// A tracked mono label: "TOKENS PER DAY".
    fn lab(&self, text: &str) -> Div {
        div().font_family("Geist Mono").text_size(px(11.)).font_weight(FontWeight::MEDIUM).text_color(self.theme.muted).child(text.to_uppercase())
    }

    fn card(&self) -> Div {
        let t = self.theme;
        div().flex().flex_col().rounded(px(12.)).bg(t.card).border_1().border_color(t.border)
    }

    fn card_head(&self, title: &str, hint: Option<String>) -> Div {
        let t = self.theme;
        div()
            .flex()
            .items_center()
            .justify_between()
            .gap(px(8.))
            .px(px(24.))
            .pt(px(20.))
            .pb(px(6.))
            .child(self.lab(title))
            .children(hint.map(|h| div().text_size(px(12.)).text_color(t.muted).child(h)))
    }

    fn bar(&self, used: f64, pace: Option<f64>) -> impl IntoElement {
        let t = self.theme;
        let fill = if used >= 90.0 { t.bad } else if used >= 75.0 { t.warn } else { t.ink };
        let share = (used / 100.0).clamp(0.0, 1.0) as f32;
        div()
            .relative()
            .h(px(4.))
            .w_full()
            .rounded(px(2.))
            .bg(t.track)
            .child(div().absolute().top_0().left_0().h_full().w(relative(share)).rounded(px(2.)).bg(fill))
            .children(pace.map(|p| div().absolute().top(px(-3.)).h(px(10.)).w(px(2.)).left(relative(p.clamp(0.0, 1.0) as f32)).bg(t.muted)))
    }

    fn button(&self, id: String, label: String, primary: bool, account: String, cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        div()
            .id(SharedString::from(id))
            .flex_none()
            .px(px(12.))
            .h(px(28.))
            .rounded(px(7.))
            .when(primary, |d| d.bg(t.primary).text_color(t.on_primary))
            .when(!primary, |d| d.border_1().border_color(t.border).bg(t.accent).text_color(t.text))
            .text_size(px(12.))
            .font_weight(FontWeight::SEMIBOLD)
            .flex()
            .items_center()
            .cursor_pointer()
            .on_click(cx.listener(move |this, _, _, cx| this.hop(account.clone(), cx)))
            .child(label)
    }

    /// A tool's place in a list: its initials on a quiet tile, until the marks are drawn here too.
    fn tile(&self, name: &str) -> Div {
        let t = self.theme;
        let initials: String = name.split(|c: char| c == ' ' || c == '/' || c == '-').filter_map(|w| w.chars().next()).take(2).collect();
        div()
            .flex_none()
            .size(px(28.))
            .rounded(px(8.))
            .bg(t.accent)
            .border_1()
            .border_color(t.border)
            .flex()
            .items_center()
            .justify_center()
            .font_family("Geist Mono")
            .text_size(px(10.))
            .font_weight(FontWeight::BOLD)
            .text_color(t.text)
            .child(initials.to_uppercase())
    }

    // MARK: Sidebar

    fn nav_item(&self, id: &'static str, label: &'static str, section: Option<Section>, page: &'static str, count: usize, cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let on = section == Some(self.section);
        div()
            .id(id)
            .flex()
            .items_center()
            .gap(px(10.))
            .h(px(34.))
            .px(px(10.))
            .rounded(px(8.))
            .text_size(px(13.))
            .text_color(if on { t.text } else { Theme::tint(t.text, 0.86) })
            .when(on, |d| d.bg(t.accent2).font_weight(FontWeight::SEMIBOLD))
            .hover(|s| s.bg(t.accent))
            .cursor_pointer()
            .on_click(cx.listener(move |this, _, _, cx| match section {
                Some(section) => {
                    this.section = section;
                    cx.notify();
                }
                None => this.open_page(page, cx),
            }))
            .child(div().flex_1().child(label))
            .when(section.is_none(), |d| d.child(div().text_size(px(12.)).text_color(t.subtle).child("↗")))
            .when(count > 0, |d| {
                d.child(
                    div()
                        .px(px(6.))
                        .h(px(20.))
                        .rounded(px(6.))
                        .bg(Theme::tint(rgb(0xe05746), 0.16))
                        .text_color(t.bad)
                        .text_size(px(11.))
                        .font_weight(FontWeight::SEMIBOLD)
                        .flex()
                        .items_center()
                        .child(count.to_string()),
                )
            })
    }

    fn sidebar(&self, tools: &[Tool], needs: usize, cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let target = model::best_hop(tools).map(|hop| hop.to.id.clone());
        let logins: usize = tools.iter().map(|tool| tool.accounts.len()).sum();
        let used_tools = tools.iter().filter(|tool| !tool.accounts.is_empty()).count();
        let read = self.state.as_ref().and_then(|s| s.status.refreshed_at.clone());
        let fresh = read.as_deref().and_then(model::epoch).is_some_and(|at| model::now() - at < 15 * 60);
        // Each tool's login in use, its tightest window and what is left of it.
        let limits: Vec<_> = tools
            .iter()
            .filter_map(|tool| {
                let account = tool.accounts.iter().find(|a| a.active)?;
                let top = model::tightest(account);
                if top.is_none() && account.error.is_none() {
                    return None;
                }
                let left = top.map(|l| (100.0 - l.used_percent).max(0.0));
                let label = match top {
                    Some(l) => format!("{} · {}", tool.name, short_window(&l.label)),
                    None => tool.name.clone(),
                };
                let when = if account.error.is_some() {
                    "signed out".to_string()
                } else {
                    top.and_then(|l| l.resets_at.as_deref()).map(model::until).unwrap_or_default()
                };
                let fill = match left {
                    _ if account.error.is_some() => rgb(0xe05746),
                    Some(l) if l <= 15.0 => rgb(0xe05746),
                    Some(l) if l <= 40.0 => t.warn,
                    _ => Theme::tint(t.text, 0.78),
                };
                let id = tool.id.clone();
                let on = self.section == Section::Limits && self.quota_tool == tool.id;
                Some(
                    div()
                        .id(SharedString::from(format!("side-{}", tool.id)))
                        .flex()
                        .flex_col()
                        .gap(px(6.))
                        .px(px(10.))
                        .py(px(8.))
                        .rounded(px(8.))
                        .when(on, |d| d.bg(t.accent2))
                        .hover(|s| s.bg(t.accent))
                        .cursor_pointer()
                        .on_click(cx.listener(move |this, _, _, cx| {
                            this.quota_tool = if this.section == Section::Limits && this.quota_tool == id { "all".into() } else { id.clone() };
                            this.section = Section::Limits;
                            cx.notify();
                        }))
                        .child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(8.))
                                .text_size(px(12.))
                                .child(div().flex_1().min_w_0().truncate().text_color(t.text).child(label))
                                .child(div().text_color(if account.error.is_some() { t.bad } else { t.subtle }).child(when))
                                .children(left.map(|l| div().w(px(32.)).flex().justify_end().font_weight(FontWeight::SEMIBOLD).text_color(if l <= 15.0 { t.bad } else { t.text }).child(format!("{l:.0}%")))),
                        )
                        .child(div().h(px(4.)).w_full().rounded(px(2.)).bg(t.track).child(div().h_full().w(relative((left.unwrap_or(0.0) / 100.0) as f32)).rounded(px(2.)).bg(fill))),
                )
            })
            .collect();
        let login = self.state.as_ref().filter(|s| s.cloud.linked).and_then(|s| s.cloud.login.clone());
        div()
            .flex()
            .flex_col()
            .w(px(256.))
            .h_full()
            .flex_none()
            .bg(t.sidebar)
            .border_r_1()
            .border_color(t.border)
            .px(px(14.))
            .pt(px(18.))
            .pb(px(14.))
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(12.))
                    .h(px(40.))
                    .px(px(4.))
                    .child(div().flex_none().child(mark_glyph(t.text, t.blue, 22.)))
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(2.))
                            .min_w_0()
                            .child(div().text_size(px(14.)).font_weight(FontWeight::SEMIBOLD).text_color(t.text).child("Keyhop"))
                            .child(div().truncate().text_size(px(12.)).text_color(t.muted).child(format!("{logins} logins · {used_tools} tools"))),
                    ),
            )
            .child(
                div()
                    .id("hop")
                    .mt(px(16.))
                    .mx(px(2.))
                    .flex()
                    .items_center()
                    .gap(px(8.))
                    .h(px(36.))
                    .px(px(11.))
                    .rounded(px(8.))
                    .border_1()
                    .border_color(Theme::tint(t.text, 0.16))
                    .text_size(px(13.))
                    .text_color(t.muted)
                    .cursor_pointer()
                    .hover(|s| s.bg(t.accent))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        if let Some(id) = target.clone() {
                            this.hop(id, cx);
                        } else {
                            this.toast = Some("Every login in use already has the most room.".into());
                            cx.notify();
                        }
                    }))
                    .child(div().flex_1().child("Hop to a login…"))
                    .child(div().px(px(5.)).h(px(20.)).rounded(px(5.)).bg(t.accent2).font_family("Geist Mono").text_size(px(11.)).flex().items_center().child(if cfg!(target_os = "macos") { "⌘K" } else { "Ctrl K" })),
            )
            .child(div().mt(px(26.)).mb(px(8.)).px(px(8.)).child(self.lab("Platform").text_color(t.subtle)))
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(2.))
                    .child(self.nav_item("nav-home", "Home", Some(Section::Home), "overview", 0, cx))
                    .child(self.nav_item("nav-limits", "Limits", Some(Section::Limits), "limits", needs, cx))
                    .child(self.nav_item("nav-usage", "Usage", None, "usage", 0, cx))
                    .child(self.nav_item("nav-insights", "Insights", None, "coach", 0, cx))
                    .child(self.nav_item("nav-community", "Community", None, "leaderboard", 0, cx)),
            )
            .child(
                div()
                    .mt(px(26.))
                    .mb(px(8.))
                    .px(px(8.))
                    .flex()
                    .items_center()
                    .justify_between()
                    .child(self.lab("Limits").text_color(t.subtle))
                    .when(read.is_some(), |d| {
                        d.child(
                            div()
                                .flex()
                                .items_center()
                                .gap(px(6.))
                                .text_size(px(12.))
                                .text_color(if fresh { t.good } else { t.subtle })
                                .when(fresh, |d| d.child(div().size(px(6.)).rounded(px(3.)).bg(t.good)))
                                .child(if fresh { "Live".to_string() } else { format!("read {}", model::ago(read.as_deref().unwrap_or_default())) }),
                        )
                    }),
            )
            .child(div().flex_1().h(px(0.)).min_h_0().overflow_hidden().child(div().id("tree").size_full().overflow_y_scroll().flex().flex_col().gap(px(4.)).children(limits)))
            .child(
                div()
                    .flex()
                    .items_center()
                    .gap(px(10.))
                    .h(px(56.))
                    .mt(px(4.))
                    .pt(px(8.))
                    .px(px(8.))
                    .border_t_1()
                    .border_color(Theme::tint(t.text, 0.07))
                    .child(
                        div()
                            .flex_none()
                            .size(px(32.))
                            .rounded(px(7.))
                            .bg(Theme::tint(t.primary, 0.25))
                            .flex()
                            .items_center()
                            .justify_center()
                            .text_size(px(12.))
                            .font_weight(FontWeight::SEMIBOLD)
                            .child(login.as_deref().map(|l| l.chars().take(2).collect::<String>().to_uppercase()).unwrap_or_else(|| "K".into())),
                    )
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .min_w_0()
                            .child(div().truncate().text_size(px(13.)).font_weight(FontWeight::SEMIBOLD).child(login.as_deref().map(|l| format!("@{l}")).unwrap_or_else(|| "This computer".into())))
                            .child(div().truncate().text_size(px(12.)).text_color(t.muted).child(if login.is_some() { "Linked with GitHub" } else { "Not linked" })),
                    ),
            )
    }

    // MARK: Top bar

    fn topbar(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let title = match self.section {
            Section::Home => "Home",
            Section::Limits => "Limits",
        };
        // What is being read, or what a hop said, only while it matters; the sidebar says when the
        // limits were last read.
        let reading = self.state.as_ref().is_some_and(|s| s.refreshing);
        let line = self.toast.clone().or_else(|| reading.then(|| "Reading limits…".to_string())).unwrap_or_default();
        let sample = self.state.as_ref().is_some_and(|s| s.mode == "sample");
        let controls: AnyElement = match self.section {
            Section::Home => self.segmented(RANGES.iter().map(|(id, label)| (id.to_string(), label.to_string(), None)).collect(), self.range, cx).into_any_element(),
            Section::Limits => {
                let kept: Vec<&Tool> = self.state.as_ref().map(|s| s.status.tools.iter().filter(|tool| !tool.accounts.is_empty()).collect()).unwrap_or_default();
                let total: usize = kept.iter().map(|tool| tool.accounts.len()).sum();
                let mut tabs = vec![("all".to_string(), "All".to_string(), Some(total))];
                tabs.extend(kept.iter().map(|tool| (tool.id.clone(), tool.name.clone(), Some(tool.accounts.len()))));
                self.segmented(tabs, &self.quota_tool.clone(), cx).into_any_element()
            }
        };
        div()
            .flex()
            .items_center()
            .gap(px(14.))
            .h(px(60.))
            .flex_none()
            .pl(px(28.))
            .pr(px(16.))
            .border_b_1()
            .border_color(Theme::tint(t.text, 0.07))
            .child(div().flex_none().text_size(px(15.)).font_weight(FontWeight::SEMIBOLD).child(title))
            .child(div().min_w_0().overflow_hidden().child(controls))
            .child(div().flex_1())
            .when(!line.is_empty(), |d| d.child(div().flex_none().text_size(px(12.)).text_color(t.muted).child(line)))
            .when(sample, |d| d.child(div().flex_none().px(px(8.)).h(px(24.)).rounded(px(6.)).bg(Theme::tint(t.warn, 0.18)).text_color(t.warn_ink).text_size(px(12.)).font_weight(FontWeight::SEMIBOLD).flex().items_center().child("Sample")))
            .child(
                div()
                    .id("refresh")
                    .flex_none()
                    .size(px(34.))
                    .rounded(px(8.))
                    .bg(t.card)
                    .border_1()
                    .border_color(t.border)
                    .flex()
                    .items_center()
                    .justify_center()
                    .text_size(px(15.))
                    .text_color(t.muted)
                    .cursor_pointer()
                    .hover(|s| s.text_color(t.text))
                    .on_click(cx.listener(|this, _, _, cx| this.refresh(cx)))
                    .child("↻"),
            )
    }

    /// A segmented control: Home's ranges, or Limits' tools with their login counts.
    fn segmented(&self, options: Vec<(String, String, Option<usize>)>, current: &str, cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let home = self.section == Section::Home;
        div().flex().p(px(3.)).gap(px(2.)).rounded(px(8.)).bg(t.card).border_1().border_color(t.border).children(options.into_iter().map(|(id, label, n)| {
            let on = id == current;
            let pick = id.clone();
            div()
                .id(SharedString::from(format!("seg-{id}")))
                .flex()
                .items_center()
                .gap(px(6.))
                .h(px(28.))
                .px(px(14.))
                .rounded(px(6.))
                .text_size(px(12.))
                .when(on, |d| d.bg(t.accent2).text_color(t.text).font_weight(FontWeight::SEMIBOLD))
                .when(!on, |d| d.text_color(t.muted).font_weight(FontWeight::MEDIUM))
                .cursor_pointer()
                .hover(|s| s.text_color(t.text))
                .on_click(cx.listener(move |this, _, _, cx| {
                    if home {
                        if let Some((range, _)) = RANGES.iter().find(|(r, _)| *r == pick) {
                            this.set_range(range, cx);
                        }
                    } else {
                        this.quota_tool = pick.clone();
                        cx.notify();
                    }
                }))
                .child(label)
                .children(n.map(|n| div().opacity(0.6).child(n.to_string())))
        }))
    }

    // MARK: Home

    fn total_card(&self, usage: &Usage) -> impl IntoElement {
        let t = self.theme;
        let (label, title, span) = match self.range {
            "today" => ("Today", "Today, so far", "yesterday"),
            "month" => ("This month", "This month, so far", "the month before"),
            "all" => ("All time", "Everything so far", "the period before"),
            _ => ("7 days", "The last 7 days", "the 7 days before"),
        };
        let total = &usage.total;
        let change = (usage.compared && usage.previous.tokens > 0).then(|| {
            let pct = ((total.tokens as f64 - usage.previous.tokens as f64) / usage.previous.tokens as f64 * 100.0).round();
            (pct, format!("{} {:.0}% on {span}", if pct >= 0.0 { "↑" } else { "↓" }, pct.abs()))
        });
        let mut tools: Vec<_> = usage.tools.iter().filter(|tool| tool.figures.tokens > 0).collect();
        tools.sort_by(|a, b| b.figures.tokens.cmp(&a.figures.tokens));
        let sum = tools.iter().map(|tool| tool.figures.tokens).sum::<u64>().max(1) as f64;
        let colour = |i: usize| rgb(model::SHARE_GREYS[i.min(model::SHARE_GREYS.len() - 1)]);
        let side = total.input + total.cache_read + total.cache_write;
        let mut facts = vec![format!("{} requests", model::count(total.requests))];
        if side > 0 {
            let hit = total.cache_read as f64 / side as f64 * 100.0;
            facts.push(if usage.cache_savings > 0.0 { format!("{hit:.0}% from cache, {} saved", usd(usage.cache_savings)) } else { format!("{hit:.0}% from cache") });
        }
        self.card()
            .flex_none()
            .gap(px(20.))
            .px(px(26.))
            .pt(px(24.))
            .pb(px(26.))
            .child(
                div()
                    .flex()
                    .items_start()
                    .justify_between()
                    .child(div().flex().flex_col().gap(px(6.)).child(self.lab(&format!("{} · {label}", self.today.split(", ").nth(1).unwrap_or(&self.today)))).child(div().text_size(px(26.)).font_weight(FontWeight::MEDIUM).child(title)))
                    .children(change.map(|(pct, text)| div().text_size(px(12.)).font_weight(FontWeight::SEMIBOLD).text_color(if pct >= 0.0 { t.good } else { t.bad }).child(text))),
            )
            .child(
                div()
                    .flex()
                    .items_end()
                    .gap(px(20.))
                    .child(div().text_size(px(56.)).line_height(px(56.)).font_weight(FontWeight::MEDIUM).child(model::count(total.tokens)))
                    .child(div().flex().flex_col().pb(px(2.)).child(div().text_size(px(20.)).font_weight(FontWeight::MEDIUM).text_color(t.good).child(usd(total.cost))).child(div().text_size(px(13.)).text_color(t.muted).child("tokens · value at API prices"))),
            )
            .when(!tools.is_empty(), |d| {
                d.child(div().flex().h(px(8.)).gap(px(2.)).rounded(px(4.)).overflow_hidden().children(tools.iter().enumerate().map(|(i, tool)| div().h_full().w(relative((tool.figures.tokens as f64 / sum) as f32)).bg(colour(i)))))
                    .child(div().flex().pt(px(18.)).border_t_1().border_color(Theme::tint(t.text, 0.08)).children(tools.iter().take(6).enumerate().map(|(i, tool)| {
                        let share = tool.figures.tokens as f64 / sum * 100.0;
                        div()
                            .flex_1()
                            .min_w_0()
                            .flex()
                            .flex_col()
                            .gap(px(6.))
                            .when(i > 0, |d| d.pl(px(14.)).border_l_1().border_color(Theme::tint(t.text, 0.08)))
                            .pr(px(14.))
                            .child(div().truncate().text_size(px(12.)).font_weight(FontWeight::MEDIUM).text_color(t.muted).child(tool.name.clone()))
                            .child(div().flex().items_center().gap(px(7.)).text_size(px(18.)).font_weight(FontWeight::MEDIUM).child(div().size(px(8.)).rounded(px(2.)).bg(colour(i))).child(if share < 1.0 { "<1%".to_string() } else { format!("{share:.0}%") }))
                            .child(div().truncate().text_size(px(11.)).text_color(t.subtle).child(format!("{} tokens", model::tokens(tool.figures.tokens))))
                    })))
            })
            .child(div().flex().gap(px(10.)).text_size(px(12.)).text_color(t.muted).child(facts.join("  ·  ")))
    }

    fn trend_card(&self, usage: &Usage) -> impl IntoElement {
        let t = self.theme;
        let week = self.range == "week";
        let bars = model::trend(usage, week);
        let peak = bars.iter().map(|b| b.tokens).max().unwrap_or(1).max(1) as f64;
        let step = 10f64.powf(peak.log10().floor());
        let top = (peak / step).ceil() * step;
        let unit = match usage.bucket.as_str() {
            "hour" => "hour",
            "week" => "week",
            "month" => "month",
            _ => "day",
        };
        let last = bars.len().saturating_sub(1);
        let today = self.state.as_ref().map(|s| s.status.today.tokens);
        let label = |b: &model::DayBar| if unit == "hour" { String::new() } else { model::short_day(&b.day) };
        let height = 150.0_f32;
        self.card()
            .flex_none()
            .child(self.card_head(
                &format!("Tokens per {unit}"),
                Some(format!("{}{}", if week { "▪ 7 days before   ▪ Last 7 days   " } else { "" }, today.map(|t| format!("today {}", model::tokens(t))).unwrap_or_default())),
            ))
            .child(
                div()
                    .flex()
                    .gap(px(10.))
                    .px(px(26.))
                    .pt(px(14.))
                    .pb(px(20.))
                    .child(div().flex().flex_col().justify_between().h(px(height)).text_size(px(11.)).text_color(t.subtle).child(model::tokens(top as u64)).child(model::tokens((top / 2.0) as u64)).child("0"))
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .flex()
                            .flex_col()
                            .gap(px(8.))
                            .child(div().h(px(height)).flex().items_end().gap(px(8.)).border_t_1().border_color(Theme::tint(t.text, 0.05)).children(bars.iter().enumerate().map(|(i, b)| {
                                let fill = if i == last { t.primary } else if b.before { Theme::tint(t.text, 0.16) } else { Theme::tint(t.text, 0.55) };
                                div().flex_1().max_w(px(34.)).h(px(((b.tokens as f64 / top) as f32 * height).max(if b.tokens > 0 { 2.0 } else { 0.0 }))).rounded_t(px(3.)).bg(fill)
                            })))
                            .child(
                                div()
                                    .flex()
                                    .justify_between()
                                    .text_size(px(11.))
                                    .text_color(t.subtle)
                                    .child(bars.first().map(label).unwrap_or_default())
                                    .child(bars.get(bars.len() / 2).map(label).unwrap_or_default())
                                    .child(div().text_color(t.text).child(match unit {
                                        "hour" => "Now",
                                        "month" => "This month",
                                        "week" => "This week",
                                        _ => "Today",
                                    })),
                            ),
                    ),
            )
    }

    fn models_card(&self, usage: &Usage) -> impl IntoElement {
        let t = self.theme;
        let mut models: Vec<_> = usage.models.iter().filter(|m| m.figures.tokens > 0).collect();
        models.sort_by(|a, b| b.figures.tokens.cmp(&a.figures.tokens));
        let sum = usage.total.tokens.max(1) as f64;
        let lead = models.first().map(|m| m.figures.tokens as f64 / sum).unwrap_or(1.0).max(0.0001);
        let tools: HashMap<&str, &str> = usage.tools.iter().map(|tool| (tool.id.as_str(), tool.name.as_str())).collect();
        let span = match self.range {
            "today" => "today",
            "month" => "this month",
            "all" => "all time",
            _ => "the last 7 days",
        };
        self.card()
            .flex_none()
            .child(self.card_head("Top models", Some(format!("share of tokens {span}"))))
            .child(div().flex().flex_col().gap(px(2.)).px(px(26.)).pt(px(6.)).pb(px(16.)).children(models.iter().take(4).enumerate().map(|(i, m)| {
                let share = m.figures.tokens as f64 / sum;
                let tool = tools.get(m.tool.as_str()).copied().unwrap_or(m.tool.as_str());
                div()
                    .flex()
                    .items_center()
                    .gap(px(14.))
                    .h(px(44.))
                    .child(self.tile(tool))
                    .child(div().w(relative(0.32)).min_w_0().flex().flex_col().child(div().truncate().text_size(px(13.)).child(m.model.clone())).child(div().text_size(px(11.)).text_color(t.subtle).child(format!("via {tool}"))))
                    .child(div().flex_1().h(px(4.)).rounded(px(2.)).bg(t.track).child(div().h_full().w(relative((share / lead) as f32)).rounded(px(2.)).bg(if i == 0 { t.primary } else { Theme::tint(t.text, 0.55) })))
                    .child(div().w(px(44.)).flex().justify_end().text_size(px(13.)).font_weight(FontWeight::SEMIBOLD).child(if share < 0.01 { "<1%".to_string() } else { format!("{:.0}%", share * 100.0) }))
            })))
    }

    /// The pet's night: its stage, how far to the next, and the hop it would make in its own words.
    fn pet_card(&self, tools: &[Tool], cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let line = model::headline(tools);
        let pet = self.pet.clone();
        let streak = pet.as_ref().map(|p| p.streak).or_else(|| self.usage.get("week").map(|u| u.streak.current)).unwrap_or(0);
        let (stage_at, share) = pet.as_ref().map(model::stage_progress).unwrap_or((usize::MAX, 0.0));
        let title = match &pet {
            Some(p) => match &p.lineage_name {
                Some(lineage) => format!("{} · {lineage}", p.stage_name),
                None => p.stage_name.clone(),
            },
            None => "Your pet".into(),
        };
        let quiet = self.later.as_deref() == Some(line.title.as_str());
        let later_title = line.title.clone();
        let drawn = pet.clone();
        // The pet stands on a quiet tonal panel; the 2.0 world keeps no star scene.
        div()
            .relative()
            .flex()
            .flex_col()
            .min_h(px(400.))
            .rounded(px(8.))
            .overflow_hidden()
            .bg(t.card)
            .border_1()
            .border_color(t.border)
            .child(
                div()
                    .relative()
                    .flex()
                    .items_center()
                    .justify_between()
                    .px(px(24.))
                    .pt(px(22.))
                    .child(self.lab(&title))
                    .when(streak > 0, |d| d.child(div().flex().items_center().gap(px(6.)).h(px(22.)).px(px(8.)).rounded(px(6.)).bg(t.accent2).text_size(px(11.)).font_weight(FontWeight::SEMIBOLD).child(div().size(px(6.)).rounded(px(3.)).bg(rgb(0xd9a03a))).child(format!("On a {streak}-day streak")))),
            )
            .children(pet.as_ref().map(|p| {
                div()
                    .relative()
                    .flex()
                    .flex_col()
                    .gap(px(6.))
                    .px(px(24.))
                    .pt(px(14.))
                    .child(div().flex().justify_between().text_size(px(12.)).text_color(t.muted).child(format!("About {} so far", model::tokens(p.tokens))).child(p.next.as_ref().map(|n| format!("{} tokens until {}", model::tokens(n.tokens), n.label)).unwrap_or_else(|| "Fully grown".into())))
                    .child(div().h(px(4.)).rounded(px(2.)).bg(t.track).child(div().h_full().w(relative(share)).rounded(px(2.)).bg(t.primary)))
            }))
            .child(
                div()
                    .relative()
                    .flex_1()
                    .min_h(px(190.))
                    .flex()
                    .items_end()
                    .justify_between()
                    .gap(px(12.))
                    .pl(px(24.))
                    .pr(px(28.))
                    .pb(px(26.))
                    .when(!quiet, |d| {
                        d.child(
                            div()
                                .min_w_0().flex_shrink(1.).max_w(px(210.))
                                .mb(px(64.))
                                .p(px(12.))
                                .rounded(px(8.))
                                .bg(rgb(0x201d19))
                                .border_1()
                                .border_color(t.border)
                                .text_color(t.text)
                                .text_size(px(13.))
                                .flex()
                                .flex_col()
                                .gap(px(2.))
                                .child(div().font_weight(FontWeight::SEMIBOLD).child(line.title.clone()))
                                .child(div().text_color(t.muted).child(line.sub.clone()))
                                .when(!line.note.is_empty(), |d| d.child(div().text_color(t.warn_ink).child(line.note.clone())))
                                .children(line.target.clone().map(|id| {
                                    div()
                                        .flex()
                                        .gap(px(6.))
                                        .mt(px(8.))
                                        .child(self.button("pet-hop".into(), "Hop".into(), true, id, cx))
                                        .child(
                                            div()
                                                .id("pet-later")
                                                .px(px(10.))
                                                .h(px(28.))
                                                .rounded(px(5.))
                                                .bg(t.accent)
                                                .text_color(t.muted)
                                                .text_size(px(12.))
                                                .font_weight(FontWeight::MEDIUM)
                                                .flex()
                                                .items_center()
                                                .cursor_pointer()
                                                .on_click(cx.listener(move |this, _, _, cx| {
                                                    this.later = Some(later_title.clone());
                                                    cx.notify();
                                                }))
                                                .child("Later"),
                                        )
                                })),
                        )
                    })
                    .child(div().flex_1())
                    .child(
                        div()
                            .flex_none()
                            .flex()
                            .flex_col()
                            .items_center()
                            .child(pet_figure(drawn.as_ref(), 96.0, 1.0))
                            .child(div().w(px(52.)).h(px(7.)).mt(px(2.)).rounded(px(26.)).bg(rgba(0x00000073))),
                    ),
            )
            .child(
                div()
                    .relative()
                    .flex()
                    .justify_between()
                    .gap(px(4.))
                    .px(px(22.))
                    .pt(px(14.))
                    .pb(px(16.))
                    .bg(rgba(0x121110b8))
                    .border_t_1()
                    .border_color(Theme::tint(t.text, 0.06))
                    .children(model::PET_STAGES.iter().enumerate().map(|(i, (_, name, _))| {
                        let on = i == stage_at;
                        let ahead = stage_at == usize::MAX || i > stage_at;
                        div()
                            .flex()
                            .flex_col()
                            .items_center()
                            .gap(px(5.))
                            .text_size(px(11.))
                            .text_color(if on { t.text } else if ahead { t.subtle } else { t.muted })
                            .when(on, |d| d.font_weight(FontWeight::SEMIBOLD))
                            .child(
                                div()
                                    .size(px(34.))
                                    .rounded(px(7.))
                                    .flex()
                                    .items_center()
                                    .justify_center()
                                    .bg(if on { Theme::tint(t.primary, 0.18) } else { t.accent })
                                    .when(on, |d| d.border_1().border_color(t.primary))
                                    .child(pet_figure(drawn.as_ref(), 12.0 + i as f32 * 3.4, if ahead { 0.3 } else { 1.0 })),
                            )
                            .child(name.to_string())
                    })),
            )
    }

    fn activity_card(&self, usage: &Usage) -> impl IntoElement {
        let t = self.theme;
        let days: Vec<_> = usage.heatmap.iter().rev().take(17 * 7).rev().cloned().collect();
        let levels = model::heat_levels(&days);
        // The activity heatmap, as the window draws it: one neutral ramp, never a hue.
        let colours: [Rgba; 5] = [rgba(0xfffaf00d), rgba(0xfffaf02e), rgba(0xfffaf05c), rgba(0xfffaf099), rgba(0xfffaf0e6)];
        let s = &usage.streak;
        let note = if s.current > 0 {
            if s.current >= s.longest { format!("{}-day streak, your best", s.current) } else { format!("{}-day streak · best {}", s.current, s.longest) }
        } else {
            format!("{} active days", s.active_days)
        };
        // Weeks start on Monday, as on the board: the first column is padded to the first day.
        let offset = days.first().and_then(|d| model::epoch(&format!("{}T00:00:00Z", d.day))).map(|s| ((s / 86_400 + 3).rem_euclid(7)) as usize).unwrap_or(0);
        let cells: Vec<Option<u8>> = std::iter::repeat_n(None, offset).chain(levels.iter().map(|&l| Some(l))).collect();
        let columns: Vec<_> = cells
            .chunks(7)
            .map(|week| div().flex_1().flex().flex_col().gap(px(4.)).children(week.iter().map(|l| div().h(px(11.)).rounded(px(3.)).when_some(*l, |d, l| d.bg(colours[l as usize])))))
            .collect();
        self.card()
            .flex_none()
            .child(self.card_head("Activity", Some(note)))
            .child(div().flex().gap(px(4.)).px(px(24.)).pt(px(10.)).children(columns))
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .px(px(24.))
                    .pt(px(14.))
                    .pb(px(20.))
                    .text_size(px(11.))
                    .text_color(t.subtle)
                    .child(days.first().map(|d| model::short_day(&d.day)).unwrap_or_default())
                    .child(div().flex().items_center().gap(px(4.)).child("Less").children(colours.iter().map(|c| div().size(px(10.)).rounded(px(2.)).bg(*c))).child("More")),
            )
    }

    fn attention_card(&self, tools: &[Tool], cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        // What wants a decision now: a login in use at its wall, or one signed out.
        let mut rows: Vec<AnyElement> = Vec::new();
        for tool in tools {
            for account in &tool.accounts {
                let alt = model::alternative(tool, Some(account));
                let (glyph, tone, title, text, action): (&str, Rgba, String, String, Option<(String, String, bool)>) = if let Some(error) = &account.error {
                    ("⚿", t.bad, format!("{} is signed out", account.name), format!("{}. {error}", tool.name), (!account.active).then(|| ("Switch and sign in".to_string(), account.id.clone(), true)))
                } else if account.active && model::lane(account) == Lane::Needs {
                    let used = model::max_used(account);
                    let more = match alt {
                        Some(a) => format!("{} is at {:.0}%.", a.name, model::max_used(a)),
                        None => "There is no other login to hop to.".to_string(),
                    };
                    (if alt.is_some() { "↷" } else { "+" }, if alt.is_some() { t.primary } else { t.bad }, format!("{} is at {used:.0}% on {}", tool.name, account.name), more, alt.map(|a| (format!("Hop to {}", a.name), a.id.clone(), true)))
                } else {
                    continue;
                };
                let first = rows.is_empty();
                rows.push(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(12.))
                        .px(px(4.))
                        .py(px(12.))
                        .when(!first, |d| d.border_t_1().border_color(Theme::tint(t.text, 0.07)))
                        .child(div().flex_none().size(px(26.)).rounded(px(6.)).bg(Theme::tint(tone, 0.16)).text_color(tone).flex().items_center().justify_center().text_size(px(13.)).font_weight(FontWeight::BOLD).child(glyph))
                        .child(div().flex_1().min_w_0().flex().flex_col().child(div().truncate().text_size(px(13.)).font_weight(FontWeight::SEMIBOLD).child(title)).child(div().text_size(px(12.)).text_color(t.muted).child(text)))
                        .children(action.map(|(label, id, primary)| self.button(format!("attn-{}", account.id), label, primary, id, cx)))
                        .into_any_element(),
                );
            }
        }
        let count = rows.len();
        self.card()
            .flex_none()
            .child(
                div()
                    .flex()
                    .items_center()
                    .justify_between()
                    .px(px(24.))
                    .pt(px(20.))
                    .pb(px(6.))
                    .child(self.lab("Needs your attention"))
                    .when(count > 0, |d| d.child(div().px(px(6.)).h(px(20.)).rounded(px(6.)).bg(Theme::tint(rgb(0xe05746), 0.16)).text_color(t.bad).text_size(px(11.)).font_weight(FontWeight::SEMIBOLD).flex().items_center().child(count.to_string()))),
            )
            .when(count == 0, |d| d.child(div().px(px(24.)).pt(px(12.)).pb(px(20.)).text_size(px(13.)).text_color(t.muted).child("Nothing needs you. Every login in use has room.")))
            .child(div().flex().flex_col().px(px(20.)).pb(px(12.)).children(rows))
    }

    fn home(&self, tools: &[Tool], cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let usage = self.usage.get(self.range).cloned();
        let left: Vec<AnyElement> = match &usage {
            Some(u) => vec![self.total_card(u).into_any_element(), self.trend_card(u).into_any_element(), self.models_card(u).into_any_element()],
            None => vec![self.card().p(px(24.)).text_size(px(13.)).text_color(t.muted).child("Reading usage…").into_any_element()],
        };
        div()
            .id("home")
            .size_full()
            .overflow_y_scroll()
            .child(
                div()
                    .flex()
                    .items_start()
                    .gap(px(18.))
                    .px(px(24.))
                    .pt(px(20.))
                    .pb(px(28.))
                    .child(div().w(relative(0.6)).flex_none().flex().flex_col().gap(px(18.)).children(left))
                    .child(
                        div()
                            .flex_1()
                            .min_w_0()
                            .flex()
                            .flex_col()
                            .gap(px(18.))
                            .child(self.pet_card(tools, cx))
                            .children(usage.as_ref().map(|u| self.activity_card(u)))
                            .child(self.attention_card(tools, cx)),
                    ),
            )
    }

    // MARK: Limits

    /// What the pool had left over the chosen span, a column per step, with resets in green.
    fn chart(&self, quota: &Quota, pool: &Pool) -> impl IntoElement {
        let t = self.theme;
        let now = model::epoch(&quota.forecast_start).unwrap_or_else(model::now);
        let from = now - self.quota_hours * 3_600;
        let height = 150.0_f32;
        let top = pool.capacity.max(100.0);
        let columns = model::history(quota, pool, from, now, if self.quota_hours > 48 { 84 } else { 48 });
        let resets = model::reset_columns(&columns, top);
        if columns.iter().flatten().count() < 2 {
            return div().px(px(24.)).h(px(height)).flex().items_center().text_size(px(13.)).text_color(t.muted).child("Keyhop draws this once it has read the limits for a while.");
        }
        div().flex().items_end().gap(px(1.)).h(px(height)).px(px(24.)).children(columns.into_iter().zip(resets).map(|(value, reset)| {
            let share = (value.unwrap_or(0.0) / top).clamp(0.0, 1.0) as f32;
            div().flex_1().h(px(if value.is_some() { (share * height).max(1.0) } else { 0.0 })).rounded_t(px(2.)).bg(if reset { t.good } else { Theme::tint(t.ink, 0.55) })
        }))
    }

    /// 24 hours or 7 days of history.
    fn span_toggle(&self, cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        div().flex().p(px(3.)).gap(px(2.)).rounded(px(8.)).bg(t.card).border_1().border_color(t.border).children([(24_i64, "24 hours"), (168, "7 days")].into_iter().map(|(hours, label)| {
            let on = self.quota_hours == hours;
            div()
                .id(SharedString::from(format!("span-{hours}")))
                .flex()
                .items_center()
                .h(px(26.))
                .px(px(12.))
                .rounded(px(6.))
                .text_size(px(12.))
                .when(on, |d| d.bg(t.accent2).text_color(t.text).font_weight(FontWeight::SEMIBOLD))
                .when(!on, |d| d.text_color(t.muted).font_weight(FontWeight::MEDIUM))
                .cursor_pointer()
                .hover(|s| s.text_color(t.text))
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.quota_hours = hours;
                    cx.notify();
                }))
                .child(label)
        }))
    }

    fn login_line(&self, tool: &Tool, account: &Account, first: bool, cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let lane = model::lane(account);
        let meta = account.error.clone().unwrap_or_else(|| {
            let plan = [account.plan.clone().unwrap_or_default(), if account.keep_for_last { "kept for last".into() } else { String::new() }]
                .into_iter().filter(|p| !p.is_empty()).collect::<Vec<_>>().join(" · ");
            // A failed reading keeps the last good one, and says how old it is.
            match (&account.read_error, &account.limits_read_at) {
                (Some(_), Some(read)) => [plan, format!("last read {}", model::ago(read))].into_iter().filter(|p| !p.is_empty()).collect::<Vec<_>>().join(" · "),
                _ => plan,
            }
        });
        let windows = account.limits.iter().take(3).map(|limit| {
            div()
                .flex()
                .items_center()
                .gap(px(10.))
                .text_size(px(12.))
                .child(div().w(px(80.)).flex_none().truncate().text_color(t.muted).child(model::window_name(&limit.label)))
                .child(div().flex_1().child(self.bar(limit.used_percent, None)))
                .child(div().w(px(36.)).flex().justify_end().font_weight(FontWeight::SEMIBOLD).text_color(t.text).child(format!("{:.0}%", limit.used_percent)))
                .child(div().w(px(84.)).text_color(t.subtle).child(limit.resets_at.as_deref().map(|r| if model::passed(r) { "reset since".to_string() } else { format!("back in {}", model::until(r)) }).unwrap_or_default()))
        });
        let dot = match lane {
            Lane::Needs => t.bad,
            Lane::Hot | Lane::Room => t.good,
            _ => t.primary,
        };
        div()
            .flex()
            .items_center()
            .gap(px(18.))
            .px(px(20.))
            .py(px(14.))
            .when(!first, |d| d.border_t_1().border_color(Theme::tint(t.text, 0.07)))
            .when(lane == Lane::Needs && account.active, |d| d.bg(Theme::tint(rgb(0xfb414a), 0.06)))
            .child(
                div()
                    .w(px(220.))
                    .flex_none()
                    .flex()
                    .items_start()
                    .gap(px(8.))
                    .child(div().mt(px(6.)).size(px(6.)).rounded(px(3.)).flex_none().bg(dot))
                    .child(
                        div()
                            .min_w_0()
                            .flex()
                            .flex_col()
                            .child(
                                div()
                                    .flex()
                                    .items_center()
                                    .gap(px(6.))
                                    .child(div().truncate().text_size(px(13.)).font_weight(FontWeight::SEMIBOLD).child(account.name.clone()))
                                    .when(account.active, |d| d.child(div().px(px(6.)).h(px(18.)).rounded(px(5.)).bg(Theme::tint(t.primary, 0.18)).text_color(t.info).text_size(px(11.)).font_weight(FontWeight::SEMIBOLD).flex().items_center().child("In use")))
                                    .when(account.error.is_some(), |d| d.child(div().px(px(6.)).h(px(18.)).rounded(px(5.)).bg(Theme::tint(rgb(0xe05746), 0.16)).text_color(t.bad).text_size(px(11.)).font_weight(FontWeight::SEMIBOLD).flex().items_center().child("Signed out"))),
                            )
                            .child(div().truncate().text_size(px(12.)).text_color(t.muted).child(meta)),
                    ),
            )
            .child(div().flex_1().min_w_0().flex().flex_col().gap(px(8.)).children(windows).when(account.limits.is_empty(), |d| d.child(div().text_size(px(12.5)).text_color(t.subtle).child(if tool.accounts.iter().all(|a| a.limits.is_empty()) { "No limit to read." } else { "" }))))
            .child(div().w(px(130.)).flex_none().flex().justify_end().when(!account.active, |d| d.child(self.button(format!("switch-{}", account.id), if account.error.is_some() { "Hop and sign in".into() } else { "Hop here".into() }, account.error.is_none(), account.id.clone(), cx))))
    }

    /// One figure in a strip split by hairlines: "Draining 80%/h".
    fn figure(&self, label: &str, value: String, note: String, tone: Rgba, first: bool) -> impl IntoElement {
        let t = self.theme;
        div()
            .flex_1()
            .flex()
            .flex_col()
            .gap(px(4.))
            .when(!first, |d| d.pl(px(16.)).border_l_1().border_color(Theme::tint(t.text, 0.08)))
            .child(div().text_size(px(12.)).font_weight(FontWeight::MEDIUM).text_color(t.muted).child(label.to_string()))
            .child(div().text_size(px(20.)).font_weight(FontWeight::MEDIUM).text_color(tone).child(value))
            .child(div().text_size(px(11.)).text_color(t.subtle).child(note))
    }

    fn limits(&self, tools: &[Tool], cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let kept: Vec<&Tool> = tools.iter().filter(|tool| !tool.accounts.is_empty()).collect();
        let pool = self.quota.as_ref().and_then(|q| q.pools.iter().find(|p| p.tool == self.quota_tool));
        let pooled: AnyElement = match (self.quota.as_ref(), pool) {
            (Some(quota), Some(pool)) if pool.accounts > 0 => {
                let reset = pool.next_reset.as_ref();
                let one = pool.accounts == 1;
                let last_hour = model::last_hour(pool);
                let logins: Vec<&Account> = kept.iter().filter(|tool| self.quota_tool == "all" || tool.id == self.quota_tool).flat_map(|tool| tool.accounts.iter()).filter(|a| model::left(a).is_some()).collect();
                let roomy = logins.iter().filter(|a| model::left(a).unwrap_or(0.0) >= 20.0).count();
                let scope = if self.quota_tool == "all" { format!("{} login{} with limits", pool.accounts, if one { "" } else { "s" }) } else { format!("{} {} login{}", pool.accounts, pool.name, if one { "" } else { "s" }) };
                let left = self
                    .card()
                    .w(relative(0.42))
                    .flex_none()
                    .gap(px(14.))
                    .px(px(26.))
                    .py(px(24.))
                    .child(self.lab(&if one { scope } else { format!("{scope} · out of {:.0}%", pool.capacity) }))
                    .child(div().text_size(px(24.)).font_weight(FontWeight::MEDIUM).child("What your logins have left"))
                    .child(div().flex().items_end().gap(px(10.)).child(div().text_size(px(56.)).line_height(px(56.)).font_weight(FontWeight::MEDIUM).child(format!("{:.0}%", pool.remaining))).child(div().pb(px(6.)).text_size(px(13.)).text_color(t.muted).child(if one { "left" } else { "left across them all" })))
                    .when(!one, |d| d.child(div().text_size(px(13.)).text_color(t.muted).child("Each login keeps its own limits. This adds up what each one has left, so 100% is one full login.")))
                    .child(
                        div()
                            .flex()
                            .pt(px(16.))
                            .border_t_1()
                            .border_color(Theme::tint(t.text, 0.08))
                            .child(self.figure("Last hour", if last_hour >= 0.05 { if last_hour >= 10.0 { format!("{last_hour:.0}% used") } else { format!("{last_hour:.1}% used") } } else { "Nothing used".into() }, (if one { "by this login" } else { "across the logins" }).into(), t.text, true))
                            .child(match reset {
                                Some(r) => self.figure("Next reset", format!("+{:.0}%", r.gain), format!("in {} · {}", model::until(&r.at), r.account), t.good, false),
                                None => self.figure("Next reset", "None soon".into(), "no window resets this week".into(), t.text, false),
                            })
                            .child(self.figure("With room", format!("{roomy} of {}", logins.len()), "logins with 20% or more left".into(), if roomy == 0 { t.bad } else { t.text }, false)),
                    );
                let title = if self.quota_hours > 48 { "The last 7 days" } else { "The last 24 hours" };
                let right = self
                    .card()
                    .flex_1()
                    .min_w_0()
                    .pb(px(20.))
                    .child(self.card_head(title, None))
                    .child(div().pt(px(16.)).child(self.chart(quota, pool)))
                    .child(div().px(px(24.)).pt(px(14.)).flex().child(self.span_toggle(cx)));
                div().flex().gap(px(18.)).items_start().child(left).child(right).into_any_element()
            }
            (Some(_), _) => self.card().child(div().p(px(24.)).text_color(t.muted).text_size(px(13.)).child("No login here has a limit to read.")).into_any_element(),
            (None, _) => self.card().child(div().p(px(24.)).text_color(t.muted).text_size(px(13.)).child("Reading the limits' history…")).into_any_element(),
        };
        let shown: Vec<&Tool> = kept.iter().copied().filter(|tool| self.quota_tool == "all" || tool.id == self.quota_tool).collect();
        let mut groups: Vec<Div> = Vec::new();
        for tool in shown {
            let pool = self.quota.as_ref().and_then(|q| q.pools.iter().find(|p| p.tool == tool.id));
            let summary = pool.filter(|p| p.accounts > 0).map(|p| format!("{:.0}% of {:.0}% left", p.remaining, p.capacity)).unwrap_or_default();
            let wall = tool.accounts.iter().any(|a| a.active && model::lane(a) == Lane::Needs);
            let mut accounts: Vec<&Account> = tool.accounts.iter().collect();
            accounts.sort_by(|a, b| b.active.cmp(&a.active).then(model::max_used(a).total_cmp(&model::max_used(b))));
            let mut card = self.card();
            for (i, account) in accounts.into_iter().enumerate() {
                card = card.child(self.login_line(tool, account, i == 0, cx));
            }
            groups.push(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(12.))
                    .child(div().flex().items_center().gap(px(12.)).child(self.tile(&tool.name)).child(div().text_size(px(18.)).font_weight(FontWeight::MEDIUM).child(tool.name.clone())).child(div().text_size(px(12.)).text_color(if wall { t.bad } else { t.muted }).child(summary)))
                    .child(card),
            );
        }
        div().id("limits").size_full().overflow_y_scroll().child(div().flex().flex_col().px(px(24.)).pt(px(20.)).pb(px(28.)).gap(px(24.)).child(pooled).children(groups))
    }
}

/// A window's short name in the sidebar: "5h", "week".
fn short_window(label: &str) -> String {
    match label {
        "Week" => "week".into(),
        "Opus" => "Opus week".into(),
        "Sonnet" => "Sonnet week".into(),
        other => other.into(),
    }
}

fn usd(amount: f64) -> String {
    if amount >= 1000.0 {
        format!("${}", model::count(amount.round() as u64))
    } else {
        format!("${amount:.2}")
    }
}

/// Keyhop's mark, the canonical 24-grid K: the tall key, the middle key, the hopped arm in brand
/// blue, the lower arm. Bare ink on the ground, never on a tile.
fn mark_glyph(ink: Rgba, hop: Rgba, size: f32) -> impl IntoElement {
    let s = size / 24.;
    let key = move |x: f32, y: f32, w: f32, h: f32, r: f32, fill: Rgba| {
        div().absolute().left(px(x * s)).top(px(y * s)).w(px(w * s)).h(px(h * s)).rounded(px(r * s)).bg(fill)
    };
    div()
        .relative()
        .size(px(size))
        .child(key(2.5, 2.5, 6., 19.5, 2., ink))
        .child(key(9.6, 9.2, 6., 6., 1.5, ink))
        .child(key(16., 1., 6., 6., 1.5, hop))
        .child(key(16., 17., 6., 6., 1.5, ink))
}

/// The pet painted from its shapes, `height` pixels tall; nothing when there is no pet yet.
fn pet_figure(pet: Option<&Pet>, height: f32, alpha: f32) -> AnyElement {
    let Some(pet) = pet.filter(|p| p.height > 0.0 && !p.shapes.is_empty()) else {
        return div().size(px(height)).into_any_element();
    };
    let scale = height / pet.height;
    let shapes = pet.shapes.clone();
    canvas(
        |_, _, _| (),
        move |bounds, _, window, _| {
            for shape in &shapes {
                let colour = model::hex(&shape.fill);
                let fill_colour = Rgba { r: ((colour >> 16) & 255) as f32 / 255., g: ((colour >> 8) & 255) as f32 / 255., b: (colour & 255) as f32 / 255., a: shape.opacity * alpha };
                window.paint_quad(fill(Bounds::new(point(bounds.origin.x + px(shape.x * scale), bounds.origin.y + px(shape.y * scale)), size(px(shape.w * scale), px(shape.h * scale))), fill_colour));
            }
        },
    )
    .w(px(pet.width * scale))
    .h(px(height))
    .into_any_element()
}

impl Render for KeyhopWindow {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let state = self.state.clone();
        let tools: Vec<Tool> = state.as_ref().map(|s| s.status.tools.clone()).unwrap_or_default();
        let needs = tools.iter().flat_map(|tool| tool.accounts.iter()).filter(|a| model::lane(a) == Lane::Needs).count();
        let body: AnyElement = match (&self.problem, state.is_some()) {
            (Some(problem), false) => div().p(px(24.)).text_color(t.bad).child(format!("Keyhop isn't answering: {problem}")).into_any_element(),
            (_, false) => div().p(px(24.)).text_color(t.muted).child("Reading your logins…").into_any_element(),
            _ => match self.section {
                Section::Home => self.home(&tools, cx).into_any_element(),
                Section::Limits => self.limits(&tools, cx).into_any_element(),
            },
        };
        div()
            .size_full()
            .flex()
            .flex_col()
            .bg(t.bg)
            .text_color(t.text)
            .font_family("Geist")
            .child(
                div()
                    .flex()
                    .flex_1()
                    .min_h_0()
                    .child(self.sidebar(&tools, needs, cx))
                    .child(div().flex_1().min_w_0().h_full().flex().flex_col().child(self.topbar(cx)).child(div().flex_1().min_h_0().child(body))),
            )
    }
}
