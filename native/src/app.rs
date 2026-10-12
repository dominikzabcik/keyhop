//! Keyhop's window in GPUI: the sidebar, Home, Limits (pooled and projected) and the status bar,
//! drawn over the same local API the HTML window reads.

use crate::api::{Account, Client, Pool, Quota, State, Tool};
use crate::model::{self, Lane};
use crate::theme::Theme;
use gpui_kit::*;
use gpui_kit::prelude::FluentBuilder as _;
use std::time::Duration;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Section {
    Home,
    Limits,
}

pub struct KeyhopWindow {
    client: Client,
    state: Option<State>,
    quota: Option<Quota>,
    /// The tool Limits is narrowed to, or "all".
    quota_tool: String,
    problem: Option<String>,
    toast: Option<String>,
    section: Section,
    theme: Theme,
    busy: bool,
}

impl KeyhopWindow {
    pub fn new(client: Client, section: Section, theme: Option<&str>, cx: &mut Context<Self>) -> Self {
        let pinned = theme.map(str::to_string);
        let window = Self { client, state: None, quota: None, quota_tool: "all".into(), problem: None, toast: None, section, theme: Theme::named(pinned.as_deref().unwrap_or("night")), busy: false };
        // Read the state now and every twenty seconds, off the main thread.
        cx.spawn(async move |this, cx| {
            loop {
                let Ok(client) = this.read_with(cx, |this, _| this.client.clone()) else { break };
                let (result, quota) = cx.background_executor().spawn(async move { (client.state(), client.quota().ok()) }).await;
                if this
                    .update(cx, |this, cx| {
                        if quota.is_some() {
                            this.quota = quota;
                        }
                        match result {
                            Ok(state) => {
                                if pinned.is_none() {
                                    this.theme = Theme::named(&state.appearance.theme);
                                }
                                this.state = Some(state);
                                this.problem = None;
                            }
                            Err(error) => this.problem = Some(error.to_string()),
                        }
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

    fn reload(&mut self, cx: &mut Context<Self>) {
        let client = self.client.clone();
        cx.spawn(async move |this, cx| {
            let (result, quota) = cx.background_executor().spawn(async move { (client.state(), client.quota().ok()) }).await;
            let _ = this.update(cx, |this, cx| {
                if quota.is_some() {
                    this.quota = quota;
                }
                if let Ok(state) = result {
                    this.theme = Theme::named(&state.appearance.theme);
                    this.state = Some(state);
                }
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

    fn toggle_theme(&mut self, cx: &mut Context<Self>) {
        let next = if self.theme.day { "night" } else { "day" };
        self.theme = Theme::named(next);
        cx.notify();
        let client = self.client.clone();
        cx.background_executor().spawn(async move { client.set_theme(next) }).detach();
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

    // MARK: Pieces

    fn dot(&self, lane: Lane) -> impl IntoElement {
        let t = self.theme;
        let base = div().size(px(8.)).rounded(px(4.)).flex_none();
        match lane {
            Lane::Needs => base.bg(t.warn),
            Lane::Active => base.border_2().border_color(t.info),
            Lane::Hot | Lane::Room => base.bg(t.good),
            Lane::Quiet => base.border_2().border_color(t.subtle),
        }
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

    fn nav_item(&self, id: &'static str, label: &'static str, section: Section, count: usize, cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let on = self.section == section;
        div()
            .id(id)
            .flex()
            .items_center()
            .gap(px(10.))
            .h(px(32.))
            .px(px(10.))
            .rounded(px(8.))
            .text_size(px(13.))
            .text_color(if on { t.text } else { t.side })
            .when(on, |d| d.bg(t.accent2))
            .hover(|s| s.bg(t.accent))
            .cursor_pointer()
            .on_click(cx.listener(move |this, _, _, cx| {
                this.section = section;
                cx.notify();
            }))
            .child(div().flex_1().child(label))
            .when(count > 0, |d| {
                d.child(
                    div().px(px(6.)).h(px(18.)).rounded(px(9.)).bg(t.warn).text_color(if t.day { rgb(0xffffff) } else { rgb(0x1c1408) }).text_size(px(11.)).font_weight(FontWeight::BOLD).flex().items_center().child(count.to_string()),
                )
            })
    }

    fn sidebar(&self, tools: &[Tool], needs: usize, cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let target = model::best_hop(tools).map(|hop| hop.to.id.clone());
        // Each tool's login in use and how full its tightest window is; a press opens Limits on it.
        let in_use: Vec<_> = tools.iter().filter(|tool| !tool.accounts.is_empty()).map(|tool| {
            let account = tool.accounts.iter().find(|a| a.active);
            let lane = account.map(model::lane).unwrap_or(Lane::Quiet);
            let pct = account.and_then(model::tightest).map(|l| l.used_percent);
            let id = tool.id.clone();
            let on = self.section == Section::Limits && self.quota_tool == tool.id;
            div()
                .id(SharedString::from(format!("side-{}", tool.id)))
                .flex()
                .items_center()
                .gap(px(9.))
                .h(px(38.))
                .px(px(10.))
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
                        .flex_1()
                        .min_w_0()
                        .flex()
                        .flex_col()
                        .child(div().truncate().text_size(px(12.5)).font_weight(FontWeight::SEMIBOLD).text_color(t.text).child(tool.name.clone()))
                        .child(div().truncate().text_size(px(11.5)).text_color(if lane == Lane::Needs { t.warn_ink } else { t.subtle }).child(account.map(|a| a.name.clone()).unwrap_or_else(|| "None in use".into()))),
                )
                .children(pct.map(|p| div().text_size(px(11.5)).text_color(if lane == Lane::Needs { t.warn_ink } else { t.subtle }).child(format!("{p:.0}%"))))
        }).collect();
        div()
            .flex()
            .flex_col()
            .w(px(252.))
            .h_full()
            .flex_none()
            .bg(t.sidebar)
            .border_r_1()
            .border_color(t.border)
            .child(
                div().flex().items_center().gap(px(10.)).h(px(44.)).px(px(16.)).text_size(px(14.)).font_weight(FontWeight::BOLD).text_color(t.text).child(div().size(px(14.)).rounded(px(3.)).bg(t.ink)).child("Keyhop"),
            )
            .child(
                div()
                    .id("hop")
                    .mx(px(8.))
                    .mb(px(8.))
                    .flex()
                    .items_center()
                    .justify_between()
                    .h(px(32.))
                    .px(px(10.))
                    .rounded(px(8.))
                    .border_1()
                    .border_color(t.border)
                    .bg(t.accent)
                    .text_size(px(13.))
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(t.text)
                    .cursor_pointer()
                    .hover(|s| s.bg(t.accent2))
                    .on_click(cx.listener(move |this, _, _, cx| {
                        if let Some(id) = target.clone() {
                            this.hop(id, cx);
                        } else {
                            this.toast = Some("Every login in use already has the most room.".into());
                            cx.notify();
                        }
                    }))
                    .child("Hop")
                    .child(div().text_size(px(11.)).text_color(t.subtle).child("Smart Hop")),
            )
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(2.))
                    .px(px(8.))
                    .child(self.nav_item("nav-home", "Home", Section::Home, 0, cx))
                    .child(self.nav_item("nav-limits", "Limits", Section::Limits, needs, cx)),
            )
            .child(div().mt(px(14.)).px(px(16.)).pb(px(6.)).text_size(px(12.)).text_color(t.subtle).child("In use"))
            .child(div().id("tree").flex_1().overflow_y_scroll().px(px(6.)).children(in_use))
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
            .gap(px(8.))
            .h(px(46.))
            .px(px(16.))
            .border_b_1()
            .border_color(t.border)
            .child(div().text_size(px(14.)).font_weight(FontWeight::SEMIBOLD).text_color(t.text).child(title.to_string()))
            .children(hint.map(|h| div().text_size(px(12.5)).text_color(t.subtle).child(h)))
    }

    fn button(&self, id: String, label: String, primary: bool, account: String, cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        div()
            .id(SharedString::from(id))
            .flex_none()
            .px(px(10.))
            .h(px(26.))
            .rounded(px(7.))
            .when(primary, |d| d.bg(t.ink).text_color(t.on_ink))
            .when(!primary, |d| d.border_1().border_color(t.border).bg(t.accent).text_color(t.text))
            .text_size(px(12.))
            .font_weight(FontWeight::SEMIBOLD)
            .flex()
            .items_center()
            .cursor_pointer()
            .on_click(cx.listener(move |this, _, _, cx| this.hop(account.clone(), cx)))
            .child(label)
    }

    // MARK: Home

    fn home(&self, tools: &[Tool], cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let line = model::headline(tools);
        // What wants a decision now: a login in use at its wall, or one signed out.
        let mut attention: Vec<AnyElement> = Vec::new();
        for tool in tools {
            for account in &tool.accounts {
                let alt = model::alternative(tool, Some(account));
                let (title, text, action): (String, String, Option<(String, String, bool)>) = if let Some(error) = &account.error {
                    (format!("{} is signed out", account.name), format!("{}. {error}", tool.name), (!account.active).then(|| ("Switch and sign in".to_string(), account.id.clone(), false)))
                } else if account.active && model::lane(account) == Lane::Needs {
                    let used = model::max_used(account);
                    let more = match alt {
                        Some(a) => format!("{} is at {:.0}%.", a.name, model::max_used(a)),
                        None => "There is no other login to hop to.".to_string(),
                    };
                    (format!("{} is at {used:.0}% on {}", tool.name, account.name), more, alt.map(|a| (format!("Hop to {}", a.name), a.id.clone(), true)))
                } else {
                    continue;
                };
                let bad = account.error.is_some();
                attention.push(
                    div()
                        .flex()
                        .items_center()
                        .gap(px(12.))
                        .px(px(16.))
                        .py(px(12.))
                        .border_t_1()
                        .border_color(t.border)
                        .child(div().size(px(8.)).rounded(px(4.)).flex_none().bg(if bad { t.bad } else { t.warn }))
                        .child(
                            div()
                                .flex_1()
                                .min_w_0()
                                .flex()
                                .flex_col()
                                .child(div().text_size(px(13.)).font_weight(FontWeight::SEMIBOLD).text_color(t.text).child(title))
                                .child(div().text_size(px(12.5)).text_color(t.muted).child(text)),
                        )
                        .children(action.map(|(label, id, primary)| self.button(format!("attn-{}", account.id), label, primary, id, cx)))
                        .into_any_element(),
                );
            }
        }
        let count = attention.len();
        let attention_card = self
            .card()
            .flex_1()
            .min_w_0()
            .child(self.card_head("Needs your attention", (count > 0).then(|| count.to_string())))
            .when(count == 0, |d| d.child(div().px(px(16.)).py(px(18.)).text_size(px(13.)).text_color(t.muted).child("Nothing needs you. Every login in use has room.")))
            .children(attention);
        let pooled = self.quota.as_ref().and_then(|q| q.pools.iter().find(|p| p.tool == "all")).map(|p| format!("{:.0}% of {:.0}% left in all", p.remaining, p.capacity));
        let rows = tools.iter().filter_map(|tool| {
            let account = tool.accounts.iter().find(|a| a.active)?;
            let top = model::tightest(account);
            Some(
                div()
                    .flex()
                    .items_center()
                    .gap(px(12.))
                    .h(px(44.))
                    .px(px(16.))
                    .child(
                        div()
                            .w(px(150.))
                            .flex_none()
                            .flex()
                            .flex_col()
                            .child(div().text_size(px(13.)).font_weight(FontWeight::SEMIBOLD).text_color(t.text).child(tool.name.clone()))
                            .child(div().truncate().text_size(px(12.)).text_color(t.subtle).child(account.name.clone())),
                    )
                    .child(div().flex_1().children(top.map(|l| self.bar(l.used_percent, l.pace))))
                    .child(div().w(px(56.)).flex().justify_end().text_size(px(12.5)).text_color(if model::lane(account) == Lane::Needs { t.warn_ink } else { t.muted }).child(top.map(|l| format!("{:.0}%", l.used_percent)).unwrap_or_else(|| "No limit".into()))),
            )
        });
        let in_use = self.card().w(px(380.)).flex_none().child(self.card_head("In use", pooled)).child(div().py(px(4.)).children(rows));

        div()
            .id("home")
            .size_full()
            .overflow_y_scroll()
            .flex()
            .flex_col()
            .gap(px(16.))
            .p(px(24.))
            .child(
                div()
                    .flex()
                    .flex_col()
                    .gap(px(8.))
                    .p(px(28.))
                    .min_h(px(150.))
                    .rounded(px(16.))
                    .bg(if t.day { rgb(0xe7ecf2) } else { rgb(0x161a28) })
                    .border_1()
                    .border_color(t.border)
                    .child(div().text_size(px(30.)).font_weight(FontWeight::BOLD).text_color(t.text).child(line.title))
                    .child(div().max_w(px(520.)).text_size(px(14.)).text_color(t.muted).child(line.sub))
                    .when(!line.note.is_empty(), |d| d.child(div().max_w(px(520.)).text_size(px(13.)).text_color(t.warn_ink).child(line.note.clone())))
                    .children(line.target.clone().map(|id| div().mt(px(6.)).flex().child(self.button("hero-hop".into(), "Hop".into(), true, id, cx)))),
            )
            .child(div().flex().items_start().gap(px(16.)).child(attention_card).child(in_use))
    }

    // MARK: Limits

    fn chart(&self, quota: &Quota, pool: &Pool) -> impl IntoElement {
        let t = self.theme;
        let now = model::epoch(&quota.forecast_start).unwrap_or_else(model::now);
        let (from, to) = (now - 72 * 3_600, now + 168 * 3_600);
        let height = 150.0_f32;
        let top = pool.capacity.max(100.0);
        let columns = model::columns(quota, pool, from, to, 120);
        div()
            .flex()
            .items_end()
            .gap(px(1.))
            .h(px(height))
            .px(px(20.))
            .children(columns.into_iter().map(|column| {
                let (value, measured) = column.unwrap_or((0.0, true));
                let share = (value / top).clamp(0.0, 1.0) as f32;
                div().flex_1().h(px((share * height).max(1.0))).rounded_t(px(2.)).bg(if measured { Theme::tint(t.ink, 0.55) } else { Theme::tint(t.info, 0.45) })
            }))
    }

    fn outlook(&self, account: &Account) -> (String, Rgba) {
        let t = self.theme;
        if account.error.is_some() {
            return ("Sign in again".into(), t.bad);
        }
        let forecast = self.quota.as_ref().and_then(|q| q.accounts.iter().find(|a| a.id == account.id));
        if let Some(back) = forecast.and_then(|f| f.back_at.as_deref()) {
            return (format!("Back in {}", model::until(back)), t.bad);
        }
        if let Some(empty) = forecast.and_then(|f| f.empty_at.as_deref()) {
            return (format!("Empty in {}", model::until(empty)), t.warn_ink);
        }
        match forecast {
            Some(f) if f.drain_per_hour >= 0.05 => (format!("~{}", model::per_hour(f.drain_per_hour)), t.text),
            _ if account.limits.is_empty() => (String::new(), t.subtle),
            _ => ((if account.active { "Idle" } else { "Resting" }).into(), t.subtle),
        }
    }

    fn login_line(&self, tool: &Tool, account: &Account, cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let lane = model::lane(account);
        let (outlook, tone) = self.outlook(account);
        let meta = account.error.clone().unwrap_or_else(|| account.plan.clone().unwrap_or_default());
        let windows = account.limits.iter().take(3).map(|limit| {
            div()
                .flex()
                .items_center()
                .gap(px(10.))
                .text_size(px(12.))
                .child(div().w(px(90.)).flex_none().truncate().text_color(t.muted).child(model::window_name(&limit.label)))
                .child(div().flex_1().child(self.bar(limit.used_percent, limit.pace)))
                .child(div().w(px(36.)).flex().justify_end().text_color(t.text).child(format!("{:.0}%", limit.used_percent)))
                .child(div().w(px(56.)).text_color(t.subtle).child(limit.resets_at.as_deref().map(model::until).unwrap_or_default()))
        });
        div()
            .flex()
            .items_center()
            .gap(px(18.))
            .px(px(16.))
            .py(px(12.))
            .border_t_1()
            .border_color(t.border)
            .child(
                div()
                    .w(px(200.))
                    .flex_none()
                    .flex()
                    .items_start()
                    .gap(px(8.))
                    .child(div().mt(px(5.)).child(self.dot(lane)))
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
                                    .child(div().truncate().text_size(px(13.5)).font_weight(FontWeight::SEMIBOLD).text_color(if lane == Lane::Needs { t.warn_ink } else { t.text }).child(account.name.clone()))
                                    .when(account.active, |d| d.child(div().px(px(6.)).h(px(18.)).rounded(px(5.)).bg(t.accent2).text_size(px(11.)).font_weight(FontWeight::SEMIBOLD).flex().items_center().child("In use"))),
                            )
                            .child(div().truncate().text_size(px(12.)).text_color(t.muted).child(meta)),
                    ),
            )
            .child(div().flex_1().min_w_0().flex().flex_col().gap(px(5.)).children(windows).when(account.limits.is_empty(), |d| d.child(div().text_size(px(12.5)).text_color(t.subtle).child(if tool.accounts.iter().all(|a| a.limits.is_empty()) { "No limit to read." } else { "" }))))
            .child(div().w(px(120.)).flex_none().text_size(px(12.5)).font_weight(FontWeight::SEMIBOLD).text_color(tone).child(outlook))
            .child(div().w(px(130.)).flex_none().flex().justify_end().when(!account.active, |d| d.child(self.button(format!("switch-{}", account.id), if account.error.is_some() { "Switch and sign in".into() } else { "Switch".into() }, false, account.id.clone(), cx))))
    }

    fn limits(&self, tools: &[Tool], cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let kept: Vec<&Tool> = tools.iter().filter(|tool| !tool.accounts.is_empty()).collect();
        let total: usize = kept.iter().map(|tool| tool.accounts.len()).sum();
        let mut tabs: Vec<(String, String, usize)> = vec![("all".into(), "All".into(), total)];
        tabs.extend(kept.iter().map(|tool| (tool.id.clone(), tool.name.clone(), tool.accounts.len())));
        let tab_row = div().flex().flex_wrap().gap(px(6.)).children(tabs.into_iter().map(|(id, name, n)| {
            let on = self.quota_tool == id;
            let pick = id.clone();
            div()
                .id(SharedString::from(format!("tab-{id}")))
                .flex()
                .items_center()
                .gap(px(6.))
                .h(px(28.))
                .px(px(10.))
                .rounded(px(14.))
                .border_1()
                .border_color(if on { t.ink } else { t.border })
                .when(on, |d| d.bg(t.ink).text_color(t.on_ink))
                .when(!on, |d| d.text_color(t.muted))
                .text_size(px(12.5))
                .cursor_pointer()
                .on_click(cx.listener(move |this, _, _, cx| {
                    this.quota_tool = pick.clone();
                    cx.notify();
                }))
                .child(name)
                .child(div().opacity(0.6).child(n.to_string()))
        }));
        let pool = self.quota.as_ref().and_then(|q| q.pools.iter().find(|p| p.tool == self.quota_tool));
        let pooled: AnyElement = match (self.quota.as_ref(), pool) {
            (Some(quota), Some(pool)) if pool.accounts > 0 => {
                let reset = pool.next_reset.as_ref().map(|r| format!("Next reset +{:.0}% in {} · {}", r.gain, model::until(&r.at), r.account));
                let dry = match pool.empty_at.as_deref() {
                    Some(at) => format!("Runs dry in {}", model::until(at)),
                    None => "Lasts the next 7 days at this pace".to_string(),
                };
                self.card()
                    .child(
                        div()
                            .flex()
                            .flex_col()
                            .gap(px(4.))
                            .px(px(20.))
                            .pt(px(18.))
                            .pb(px(10.))
                            .child(div().text_size(px(12.5)).text_color(t.muted).child(format!("Remaining, pooled · {} login{} with limits", pool.accounts, if pool.accounts == 1 { "" } else { "s" })))
                            .child(
                                div()
                                    .flex()
                                    .items_baseline()
                                    .gap(px(8.))
                                    .child(div().text_size(px(38.)).font_weight(FontWeight::BOLD).text_color(t.text).child(format!("{:.0}%", pool.remaining)))
                                    .child(div().text_size(px(18.)).text_color(t.subtle).child(format!("/ {:.0}%", pool.capacity)))
                                    .child(div().ml(px(6.)).px(px(8.)).rounded(px(10.)).bg(t.accent2).text_size(px(12.5)).text_color(t.muted).child(if pool.drain_per_hour >= 0.05 { format!("~{}", model::per_hour(pool.drain_per_hour)) } else { "Not draining now".into() })),
                            ),
                    )
                    .child(self.chart(quota, pool))
                    .child(
                        div()
                            .flex()
                            .gap(px(20.))
                            .px(px(20.))
                            .py(px(12.))
                            .border_t_1()
                            .border_color(t.border)
                            .text_size(px(12.5))
                            .text_color(t.muted)
                            .children(reset)
                            .child(dry)
                            .child(div().flex_1())
                            .child("3 days measured · 7 days projected"),
                    )
                    .into_any_element()
            }
            (Some(_), _) => self.card().child(div().p(px(20.)).text_color(t.muted).text_size(px(13.)).child("No login here has a limit to read.")).into_any_element(),
            (None, _) => self.card().child(div().p(px(20.)).text_color(t.muted).text_size(px(13.)).child("Reading the limits' history…")).into_any_element(),
        };
        let shown: Vec<&Tool> = kept.iter().copied().filter(|tool| self.quota_tool == "all" || tool.id == self.quota_tool).collect();
        let mut groups: Vec<Div> = Vec::new();
        for tool in shown {
            let pool = self.quota.as_ref().and_then(|q| q.pools.iter().find(|p| p.tool == tool.id));
            let summary = pool.filter(|p| p.accounts > 0).map(|p| format!("{:.0}% of {:.0}% left", p.remaining, p.capacity));
            let mut accounts: Vec<&Account> = tool.accounts.iter().collect();
            accounts.sort_by(|a, b| b.active.cmp(&a.active).then(model::max_used(a).total_cmp(&model::max_used(b))));
            let mut card = self.card().child(self.card_head(&tool.name, summary));
            for account in accounts {
                card = card.child(self.login_line(tool, account, cx));
            }
            groups.push(card);
        }
        div().id("limits").size_full().overflow_y_scroll().flex().flex_col().p(px(20.)).gap(px(16.)).child(tab_row).child(pooled).children(groups)
    }

    fn status_bar(&self, state: Option<&State>, needs: usize, cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let today = state.map(|s| format!("{} today", model::tokens(s.status.today.tokens))).unwrap_or_default();
        let sample = state.is_some_and(|s| s.mode == "sample");
        div()
            .flex()
            .items_center()
            .gap(px(14.))
            .h(px(26.))
            .px(px(12.))
            .flex_none()
            .bg(t.sidebar)
            .border_t_1()
            .border_color(t.border)
            .text_size(px(12.))
            .text_color(t.muted)
            .when(sample, |d| d.child(div().px(px(6.)).rounded(px(4.)).bg(Theme::tint(t.warn, 0.18)).text_color(t.warn_ink).font_weight(FontWeight::SEMIBOLD).child("Sample")))
            .child(if needs > 0 { format!("{needs} need{} a hop", if needs == 1 { "s" } else { "" }) } else { "Limits clear".to_string() })
            .children(self.toast.clone().map(|toast| div().text_color(t.text).child(toast)))
            .child(div().flex_1())
            .child(today)
            .child(
                div()
                    .id("theme")
                    .cursor_pointer()
                    .hover(|s| s.text_color(t.text))
                    .on_click(cx.listener(|this, _, _, cx| this.toggle_theme(cx)))
                    .child(if t.day { "Day" } else { "Night" }),
            )
            .child(div().id("refresh").cursor_pointer().hover(|s| s.text_color(t.text)).on_click(cx.listener(|this, _, _, cx| this.refresh(cx))).child("Refresh"))
    }
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
            .font_family(".SystemUIFont")
            .child(div().flex().flex_1().min_h_0().child(self.sidebar(&tools, needs, cx)).child(div().flex_1().min_w_0().h_full().child(body)))
            .child(self.status_bar(state.as_ref(), needs, cx))
    }
}
