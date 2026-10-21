//! The local API the HTML window already reads: `keyhop dashboard` serves it on 127.0.0.1 with a
//! session key. The native window is one more client of it, so the Swift core stays the only
//! place that reads logins, limits and usage.

use anyhow::{Context as _, Result, anyhow, bail};
use serde::Deserialize;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};

#[derive(Clone)]
pub struct Client {
    base: String,
    key: String,
}

impl Client {
    /// From the address `keyhop dashboard --json` prints: `http://127.0.0.1:PORT/#s=…&k=KEY`.
    pub fn from_url(url: &str) -> Result<Self> {
        let (origin, fragment) = url.split_once('#').ok_or_else(|| anyhow!("no session key in {url}"))?;
        let key = fragment
            .split('&')
            .find_map(|part| part.strip_prefix("k="))
            .ok_or_else(|| anyhow!("no session key in {url}"))?;
        Ok(Self { base: origin.trim_end_matches('/').to_string(), key: key.to_string() })
    }

    fn get(&self, path: &str) -> Result<ureq::Response> {
        ureq::get(&format!("{}{}", self.base, path))
            .set("Authorization", &format!("Bearer {}", self.key))
            .call()
            .map_err(|error| anyhow!("{path}: {error}"))
    }

    fn post(&self, path: &str, body: serde_json::Value) -> Result<serde_json::Value> {
        let response = ureq::post(&format!("{}{}", self.base, path))
            .set("Authorization", &format!("Bearer {}", self.key))
            .send_json(body);
        match response {
            Ok(response) => Ok(response.into_json()?),
            Err(ureq::Error::Status(_, response)) => {
                let value: serde_json::Value = response.into_json().unwrap_or_default();
                bail!("{}", value.get("error").and_then(|e| e.as_str()).unwrap_or("Keyhop refused that."))
            }
            Err(error) => Err(error.into()),
        }
    }

    pub fn state(&self) -> Result<State> {
        Ok(self.get("/api/state")?.into_json()?)
    }

    /// The hop: the same call the HTML window makes.
    pub fn switch(&self, account: &str) -> Result<String> {
        let value = self.post("/api/switch", serde_json::json!({ "id": account }))?;
        Ok(value.get("message").and_then(|m| m.as_str()).unwrap_or("Hopped.").to_string())
    }

    /// Every login's limit pooled, the last week measured and the next one projected.
    pub fn quota(&self) -> Result<Quota> {
        Ok(self.get("/api/quota")?.into_json()?)
    }

    /// The usage document for a range ("today", "week", "month", "all"), every tool together.
    pub fn usage(&self, range: &str) -> Result<Usage> {
        Ok(self.get(&format!("/api/usage?range={range}&tool=all"))?.into_json()?)
    }

    /// The linked account's pet, drawn from synced totals.
    pub fn pet(&self) -> Result<Pet> {
        Ok(self.get("/api/cloud/pet")?.into_json()?)
    }

    /// The HTML window's address for a section, for the places this window doesn't draw yet.
    pub fn page(&self, section: &str) -> String {
        format!("{}/#s={section}&k={}", self.base, self.key)
    }

    pub fn set_theme(&self, theme: &str) -> Result<()> {
        self.post("/api/appearance", serde_json::json!({ "theme": theme }))?;
        Ok(())
    }

    pub fn refresh(&self) -> Result<()> {
        self.post("/api/refresh", serde_json::json!({}))?;
        Ok(())
    }
}

/// The `keyhop dashboard` this window started, stopped with it.
pub struct Server {
    child: Child,
}

impl Drop for Server {
    fn drop(&mut self) {
        let _ = self.child.kill();
    }
}

/// The Keyhop command: `KEYHOP_BIN`, the binary beside this one (inside Keyhop.app), `keyhop`
/// on PATH, or the installed app.
pub fn keyhop_binary() -> Result<PathBuf> {
    if let Ok(path) = std::env::var("KEYHOP_BIN") {
        return Ok(PathBuf::from(path));
    }
    if let Ok(me) = std::env::current_exe() {
        for name in ["Keyhop", "keyhop"] {
            let beside = me.with_file_name(name);
            if beside.is_file() && beside != me {
                return Ok(beside);
            }
        }
    }
    if let Some(paths) = std::env::var_os("PATH") {
        for dir in std::env::split_paths(&paths) {
            let candidate = dir.join("keyhop");
            if candidate.is_file() {
                return Ok(candidate);
            }
        }
    }
    let installed = PathBuf::from("/Applications/Keyhop.app/Contents/MacOS/Keyhop");
    if installed.is_file() {
        return Ok(installed);
    }
    bail!("Can't find the keyhop command. Set KEYHOP_BIN, or install Keyhop.")
}

/// Starts `keyhop dashboard --no-open --json` and waits for the address it prints.
pub fn start(sample: bool) -> Result<(Server, Client)> {
    let binary = keyhop_binary()?;
    let port = 47_000 + (std::process::id() % 2_000) as u16;
    let mut command = Command::new(&binary);
    command.args(["dashboard", "--no-open", "--json", "--port", &port.to_string()]);
    if sample {
        command.arg("--sample");
    }
    let mut child = command
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()
        .with_context(|| format!("starting {}", binary.display()))?;
    let stdout = child.stdout.take().ok_or_else(|| anyhow!("no output from keyhop"))?;
    let mut lines = BufReader::new(stdout).lines();
    let server = Server { child };
    while let Some(line) = lines.next() {
        let line = line?;
        if let Ok(value) = serde_json::from_str::<serde_json::Value>(&line) {
            if let Some(url) = value.get("url").and_then(|u| u.as_str()) {
                // Keep reading in the background so the child never blocks on a full pipe.
                std::thread::spawn(move || for _ in lines.by_ref() {});
                return Ok((server, Client::from_url(url)?));
            }
        }
    }
    bail!("keyhop dashboard ended before it printed an address")
}

// MARK: The document

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct State {
    pub status: Status,
    pub appearance: Appearance,
    pub mode: String,
    pub version: String,
    pub refreshing: bool,
    pub cloud: Cloud,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Cloud {
    pub available: bool,
    pub linked: bool,
    pub login: Option<String>,
}

/// `GET /api/usage`: tokens and API value for a range, by tool, model and step.
#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Usage {
    pub title: String,
    pub start: String,
    pub end: String,
    pub bucket: String,
    pub compared: bool,
    pub total: Figures,
    pub previous: Figures,
    pub cache_savings: f64,
    pub tools: Vec<UsageTool>,
    pub models: Vec<UsageModel>,
    pub buckets: Vec<Bucket>,
    pub heatmap: Vec<HeatDay>,
    pub streak: Streak,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Figures {
    pub tokens: u64,
    pub cost: f64,
    pub requests: u64,
    pub input: u64,
    pub cache_read: u64,
    pub cache_write: u64,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct UsageTool {
    pub id: String,
    pub name: String,
    pub figures: Figures,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct UsageModel {
    pub tool: String,
    pub model: String,
    pub figures: Figures,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Bucket {
    pub start: String,
    pub values: std::collections::HashMap<String, BucketValue>,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct BucketValue {
    pub tokens: u64,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct HeatDay {
    pub day: String,
    pub tokens: u64,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Streak {
    pub current: u32,
    pub longest: u32,
    pub active_days: u32,
}

/// `GET /api/cloud/pet`: the stage and the shapes to paint, in the pet's own units.
#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Pet {
    pub stage: String,
    pub stage_name: String,
    pub lineage_name: Option<String>,
    pub tokens: u64,
    pub next: Option<PetNext>,
    pub streak: u32,
    pub width: f32,
    pub height: f32,
    pub shapes: Vec<Shape>,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct PetNext {
    pub label: String,
    pub tokens: u64,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Shape {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
    pub fill: String,
    pub opacity: f32,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Appearance {
    pub theme: String,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Status {
    pub tools: Vec<Tool>,
    pub today: Totals,
    pub refreshed_at: Option<String>,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Totals {
    pub tokens: u64,
    pub cost: f64,
    pub requests: u64,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Tool {
    pub id: String,
    pub name: String,
    pub accounts: Vec<Account>,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Account {
    pub id: String,
    pub name: String,
    pub email: String,
    pub plan: Option<String>,
    pub active: bool,
    /// Set only when the tool turned the login down.
    pub error: Option<String>,
    /// The last reading failed for another reason; the limits are the last good ones.
    pub read_error: Option<String>,
    pub limits_read_at: Option<String>,
    pub limits: Vec<Limit>,
    pub today: Totals,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Limit {
    pub label: String,
    pub used_percent: f64,
    pub resets_at: Option<String>,
    pub runs_out_at: Option<String>,
    pub pace: Option<f64>,
}

/// `GET /api/quota`: what the Swift core's QuotaReport says.
#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Quota {
    pub step: i64,
    pub past_start: String,
    pub forecast_start: String,
    pub pools: Vec<Pool>,
    pub accounts: Vec<QuotaAccount>,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Pool {
    pub tool: String,
    pub name: String,
    pub accounts: u32,
    pub capacity: f64,
    pub remaining: f64,
    pub drain_per_hour: f64,
    pub empty_at: Option<String>,
    pub next_reset: Option<Reset>,
    pub past: Vec<Option<f64>>,
    pub forecast: Vec<f64>,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct Reset {
    pub at: String,
    pub gain: f64,
    pub account: String,
}

#[derive(Deserialize, Clone, Default, Debug)]
#[serde(rename_all = "camelCase", default)]
pub struct QuotaAccount {
    pub id: String,
    pub remaining: f64,
    pub drain_per_hour: f64,
    pub empty_at: Option<String>,
    pub back_at: Option<String>,
}
