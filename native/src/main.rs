//! keyhop-native: Keyhop's window drawn with GPUI.
//!
//!   keyhop-native            your own logins, through `keyhop dashboard`
//!   keyhop-native --sample   made-up logins, nothing of yours is read
//!   keyhop-native --url URL  attach to a dashboard that is already running
//!   --section home|limits, --theme night|day  open on a section, in a field (for screenshots)

mod api;
mod app;
mod model;
mod theme;

use gpui_kit::*;

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let sample = args.iter().any(|a| a == "--sample");
    let value = |name: &str| args.iter().position(|a| a == name).and_then(|i| args.get(i + 1)).cloned();
    let url = value("--url");
    let section = if value("--section").as_deref() == Some("limits") { app::Section::Limits } else { app::Section::Home };
    let theme = value("--theme");

    let (server, client) = match url {
        Some(url) => (None, api::Client::from_url(&url)?),
        None => {
            let (server, client) = api::start(sample)?;
            (Some(server), client)
        }
    };

    gpui_kit::application().run(move |cx| {
        gpui_kit::init(cx);
        let bounds = Bounds::centered(None, size(px(1180.), px(780.)), cx);
        let options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions { title: Some("Keyhop".into()), ..Default::default() }),
            ..Default::default()
        };
        gpui_kit::open_window(options, cx, move |_, cx| cx.new(|cx| app::KeyhopWindow::new(client, section, theme.as_deref(), cx))).expect("open the window");
        cx.activate(true);
    });
    drop(server);
    Ok(())
}
