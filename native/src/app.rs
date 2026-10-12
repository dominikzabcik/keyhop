//! Keyhop's window in GPUI: the sidebar, Overview, the Limits board and the status bar, drawn from
//! the sketch's tokens over the same local API the HTML window reads.

use crate::api::{Account, Client, State, Tool};
use crate::model::{self, Lane};
use crate::theme::Theme;
use gpui_kit::*;
use gpui_kit::prelude::FluentBuilder as _;
use std::time::Duration;

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum Section {
    Overview,
    Limits,
}

pub struct KeyhopWindow {
    client: Client,
    state: Option<State>,
    problem: Option<String>,
    toast: Option<String>,
    section: Section,
    theme: Theme,
    busy: bool,
}

impl KeyhopWindow {
    pub fn new(client: Client, section: Section, theme: Option<&str>, cx: &mut Context<Self>) -> Self {
        let pinned = theme.map(str::to_string);
        let window = Self { client, state: None, problem: None, toast: None, section, theme: Theme::named(pinned.as_deref().unwrap_or("night")), busy: false };
        // Read the state now and every twenty seconds, off the main thread.
        cx.spawn(async move |this, cx| {
            loop {
                let Ok(client) = this.read_with(cx, |this, _| this.client.clone()) else { break };
                let result = cx.background_executor().spawn(async move { client.state() }).await;
                if this
                    .update(cx, |this, cx| {
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
            let result = cx.background_executor().spawn(async move { client.state() }).await;
            let _ = this.update(cx, |this, cx| {
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
        let tree = tools.iter().filter(|tool| !tool.accounts.is_empty()).map(|tool| {
            div()
                .flex()
                .flex_col()
                .child(
                    div().flex().items_center().h(px(26.)).px(px(10.)).text_size(px(12.5)).font_weight(FontWeight::SEMIBOLD).text_color(t.side).child(tool.name.clone()),
                )
                .children(tool.accounts.iter().map(|account| {
                    div()
                        .flex()
                        .items_center()
                        .gap(px(8.))
                        .h(px(26.))
                        .pl(px(22.))
                        .pr(px(10.))
                        .text_size(px(12.5))
                        .text_color(if model::lane(account) == Lane::Needs { t.warn_ink } else { t.muted })
                        .child(self.dot(model::lane(account)))
                        .child(div().flex_1().truncate().child(account.name.clone()))
                        .child(div().text_color(t.subtle).text_size(px(11.5)).child(account.plan.clone().unwrap_or_default()))
                }))
        });
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
                    .child(self.nav_item("nav-overview", "Overview", Section::Overview, 0, cx))
                    .child(self.nav_item("nav-limits", "Limits", Section::Limits, needs, cx)),
            )
            .child(div().mt(px(14.)).px(px(16.)).pb(px(6.)).text_size(px(12.)).text_color(t.subtle).child("Accounts"))
            .child(div().id("tree").flex_1().overflow_y_scroll().px(px(6.)).children(tree))
    }

    fn login_row(&self, tool: &Tool, account: &Account, hop_target: Option<&str>, cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let lane = model::lane(account);
        let mut meta = tool.name.clone();
        if let Some(plan) = &account.plan {
            meta.push_str(&format!(" · {plan}"));
        }
        if account.error.is_some() {
            meta.push_str(" · login expired");
        } else if let Some(top) = model::tightest(account) {
            meta.push_str(&format!(" · {} {:.0}%", model::window_name(&top.label), top.used_percent));
        }
        let id = account.id.clone();
        let right: AnyElement = if account.error.is_some() {
            div().px(px(8.)).h(px(20.)).rounded(px(6.)).bg(Theme::tint(t.bad, 0.16)).text_color(t.bad).text_size(px(11.5)).font_weight(FontWeight::SEMIBOLD).flex().items_center().child("Expired").into_any_element()
        } else if lane == Lane::Needs {
            div().px(px(8.)).h(px(20.)).rounded(px(6.)).bg(Theme::tint(t.warn, 0.16)).text_color(t.warn_ink).text_size(px(11.5)).font_weight(FontWeight::SEMIBOLD).flex().items_center().child("Needs a hop").into_any_element()
        } else if hop_target == Some(account.id.as_str()) {
            div()
                .id(SharedString::from(format!("hop-{}", account.id)))
                .px(px(10.))
                .h(px(24.))
                .rounded(px(7.))
                .bg(t.ink)
                .text_color(t.on_ink)
                .text_size(px(12.))
                .font_weight(FontWeight::BOLD)
                .flex()
                .items_center()
                .cursor_pointer()
                .on_click(cx.listener(move |this, _, _, cx| this.hop(id.clone(), cx)))
                .child("Hop")
                .into_any_element()
        } else if let Some(top) = model::tightest(account) {
            div().text_size(px(12.)).text_color(t.muted).child(format!("{:.0}%", top.used_percent)).into_any_element()
        } else {
            div().into_any_element()
        };
        div()
            .flex()
            .items_center()
            .gap(px(10.))
            .h(px(32.))
            .child(self.dot(lane))
            .child(
                div()
                    .flex_1()
                    .min_w_0()
                    .flex()
                    .items_baseline()
                    .gap(px(8.))
                    .child(div().text_size(px(13.)).font_weight(FontWeight::SEMIBOLD).text_color(if lane == Lane::Needs { t.warn_ink } else { t.text }).child(account.name.clone()))
                    .child(div().truncate().text_size(px(12.5)).text_color(t.muted).child(meta)),
            )
            .child(right)
    }

    fn login_group(&self, title: &'static str, lanes: &[Lane], rows: &[(&Tool, &Account)], target: Option<&str>, cx: &mut Context<Self>) -> Option<Div> {
        let t = self.theme;
        let mut members: Vec<&(&Tool, &Account)> = rows.iter().filter(|(_, a)| lanes.contains(&model::lane(a))).collect();
        members.sort_by(|a, b| model::max_used(b.1).total_cmp(&model::max_used(a.1)));
        if members.is_empty() {
            return None;
        }
        let mut group = div().flex().flex_col().child(div().mt(px(10.)).mb(px(2.)).text_size(px(12.)).text_color(t.subtle).child(title));
        for (tool, account) in members {
            group = group.child(self.login_row(tool, account, target, cx));
        }
        Some(group)
    }

    fn overview(&self, tools: &[Tool], cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let line = model::headline(tools);
        let target = line.target.clone();
        let rows: Vec<(&Tool, &Account)> = tools.iter().flat_map(|tool| tool.accounts.iter().map(move |a| (tool, a))).collect();
        let mut groups: Vec<Div> = Vec::new();
        for (title, lanes) in [("Needs a hop", &[Lane::Needs][..]), ("In use", &[Lane::Active][..]), ("Room", &[Lane::Room, Lane::Hot][..])] {
            if let Some(group) = self.login_group(title, lanes, &rows, target.as_deref(), cx) {
                groups.push(group);
            }
        }
        let quiet: Vec<String> = tools.iter().filter(|tool| !tool.accounts.is_empty() && tool.accounts.iter().all(|a| model::lane(a) == Lane::Quiet)).map(|tool| tool.name.clone()).collect();

        div()
            .id("overview")
            .size_full()
            .overflow_y_scroll()
            .flex()
            .flex_col()
            .items_center()
            .pt(px(48.))
            .pb(px(40.))
            .px(px(24.))
            .child(div().text_size(px(28.)).font_weight(FontWeight::BOLD).text_color(t.text).child(line.title))
            .child(div().mt(px(8.)).text_size(px(14.)).text_color(t.muted).child(line.sub))
            .when(!line.note.is_empty(), |d| d.child(div().mt(px(6.)).text_size(px(13.)).text_color(t.warn_ink).child(line.note)))
            .child(
                div()
                    .mt(px(24.))
                    .w(px(620.))
                    .flex()
                    .flex_col()
                    .p(px(14.))
                    .rounded(px(12.))
                    .bg(t.card)
                    .border_1()
                    .border_color(t.border)
                    .child(div().flex().justify_between().child(div().text_size(px(13.)).font_weight(FontWeight::BOLD).text_color(t.text).child("Your logins")).child(div().text_size(px(12.)).text_color(t.subtle).child(format!("{} saved", rows.len()))))
                    .children(groups)
                    .when(!quiet.is_empty(), |d| {
                        d.child(div().mt(px(10.)).text_size(px(12.)).text_color(t.subtle).child("Quiet"))
                            .child(div().text_size(px(12.5)).text_color(t.muted).child(format!("{} have no limit to read.", quiet.join(", "))))
                    }),
            )
    }

    fn limits_column(&self, title: &'static str, lanes: &[Lane], lane_dot: Lane, rows: &[(&Tool, &Account)], cx: &mut Context<Self>) -> Div {
        let t = self.theme;
            let mut members: Vec<&(&Tool, &Account)> = rows.iter().filter(|(_, a)| lanes.contains(&model::lane(a))).collect();
        members.sort_by(|a, b| model::max_used(b.1).total_cmp(&model::max_used(a.1)));
        let count = members.len();
        div()
            .flex_1()
            .min_w(px(170.))
            .flex()
            .flex_col()
            .gap(px(10.))
            .child(div().flex().items_center().gap(px(8.)).text_size(px(13.)).font_weight(FontWeight::SEMIBOLD).text_color(t.text).child(self.dot(lane_dot)).child(div().flex_1().child(title)).child(div().text_color(t.subtle).child(count.to_string())))
            .children(members.into_iter().map(|(tool, account)| {
                let lane = model::lane(account);
                let top = model::tightest(account);
                let summary = if let Some(error) = &account.error {
                    error.clone()
                } else if account.limits.is_empty() {
                    "No limit to read.".to_string()
                } else {
                    account.limits.iter().map(|l| format!("{} {:.0}%", model::window_name(&l.label), l.used_percent)).collect::<Vec<_>>().join(" · ")
                };
                let alt = model::alternative(tool, Some(account)).filter(|_| account.active).map(|a| (a.id.clone(), a.name.clone()));
                div()
                    .flex()
                    .flex_col()
                    .gap(px(6.))
                    .p(px(12.))
                    .rounded(px(10.))
                    .bg(t.card)
                    .border_1()
                    .border_color(if lane == Lane::Needs { Theme::tint(t.warn, 0.5) } else { t.border })
                    .child(div().flex().items_center().gap(px(8.)).child(self.dot(lane)).child(div().flex_1().truncate().text_size(px(13.)).font_weight(FontWeight::SEMIBOLD).text_color(t.text).child(account.name.clone())).child(div().text_size(px(12.)).text_color(t.muted).child(top.map(|l| format!("{:.0}%", l.used_percent)).unwrap_or_default())))
                    .child(div().text_size(px(12.)).text_color(t.muted).child(format!("{}{}", tool.name, account.plan.as_ref().map(|p| format!(" · {p}")).unwrap_or_default())))
                    .child(div().text_size(px(12.5)).text_color(t.text).child(summary))
                    .children(top.map(|l| self.bar(l.used_percent, l.pace)))
                    .children(alt.map(|(id, name)| {
                        div()
                            .id(SharedString::from(format!("board-hop-{}", account.id)))
                            .text_size(px(12.))
                            .font_weight(FontWeight::SEMIBOLD)
                            .text_color(t.text)
                            .cursor_pointer()
                            .on_click(cx.listener(move |this, _, _, cx| this.hop(id.clone(), cx)))
                            .child(format!("Hop to {name}"))
                    }))
            }))
    }

    fn limits(&self, tools: &[Tool], cx: &mut Context<Self>) -> impl IntoElement {
        let t = self.theme;
        let rows: Vec<(&Tool, &Account)> = tools.iter().flat_map(|tool| tool.accounts.iter().map(move |a| (tool, a))).collect();
        div()
            .id("limits")
            .size_full()
            .overflow_y_scroll()
            .flex()
            .flex_col()
            .p(px(20.))
            .gap(px(16.))
            .child(div().flex().items_baseline().gap(px(10.)).child(div().text_size(px(15.)).font_weight(FontWeight::BOLD).text_color(t.text).child("Limits")).child(div().text_size(px(13.)).text_color(t.muted).child("Every saved login, by how close it is to a wall.")))
            .child(
                div()
                    .flex()
                    .gap(px(14.))
                    .child(self.limits_column("Needs a hop", &[Lane::Needs], Lane::Needs, &rows, cx))
                    .child(self.limits_column("In use", &[Lane::Active], Lane::Active, &rows, cx))
                    .child(self.limits_column("Room", &[Lane::Room, Lane::Hot], Lane::Room, &rows, cx))
                    .child(self.limits_column("Quiet", &[Lane::Quiet], Lane::Quiet, &rows, cx)),
            )
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
                Section::Overview => self.overview(&tools, cx).into_any_element(),
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
