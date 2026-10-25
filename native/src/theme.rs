//! The Keyhop 2.0 world, the window's tokens (Sources/Keyhop/Dashboard/Page/DashboardStyles.swift):
//! one warm charcoal ramp, color is state only, paper-on-ink actions.

use gpui_kit::{Rgba, rgb, rgba};

#[derive(Clone, Copy)]
pub struct Theme {
    pub bg: Rgba,
    pub sidebar: Rgba,
    pub card: Rgba,
    pub text: Rgba,
    pub muted: Rgba,
    pub subtle: Rgba,
    pub border: Rgba,
    pub accent: Rgba,
    pub accent2: Rgba,
    pub track: Rgba,
    pub ink: Rgba,
    /// Brand blue: only the K mark's hopped arm.
    pub blue: Rgba,
    /// The one action colour: primary buttons, paper on ink.
    pub primary: Rgba,
    pub on_primary: Rgba,
    pub warn: Rgba,
    pub warn_ink: Rgba,
    pub good: Rgba,
    pub bad: Rgba,
    pub info: Rgba,
}

impl Theme {
    pub fn world() -> Self {
        Self {
            bg: rgb(0x0c0b0a),
            sidebar: rgb(0x090807),
            card: rgb(0x121110),
            text: rgb(0xeceae5),
            muted: rgb(0xa8a49b),
            subtle: rgb(0x8b8780),
            border: rgba(0xfffaf00f),
            accent: rgba(0xfffaf00d),
            accent2: rgba(0xfffaf01c),
            track: rgb(0x201d19),
            ink: rgb(0xeceae5),
            blue: rgb(0x2f5fd9),
            primary: rgb(0xeceae5),
            on_primary: rgb(0x121110),
            warn: rgb(0xd9a03a),
            warn_ink: rgb(0xd9a03a),
            good: rgb(0x4fae72),
            bad: rgb(0xe05746),
            info: rgb(0xa8a49b),
        }
    }

    /// A colour at a share of its own alpha, for tinted pills.
    pub fn tint(color: Rgba, alpha: f32) -> Rgba {
        Rgba { a: alpha, ..color }
    }
}
