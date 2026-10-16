//! Coss Blue, the window's tokens (Sources/Keyhop/Dashboard/Page/DashboardStyles.swift), night and day.

use gpui_kit::{Rgba, rgb, rgba};

#[derive(Clone, Copy)]
pub struct Theme {
    pub day: bool,
    pub bg: Rgba,
    pub sidebar: Rgba,
    pub card: Rgba,
    pub text: Rgba,
    pub muted: Rgba,
    pub subtle: Rgba,
    pub side: Rgba,
    pub border: Rgba,
    pub accent: Rgba,
    pub accent2: Rgba,
    pub track: Rgba,
    pub ink: Rgba,
    pub on_ink: Rgba,
    /// The one action colour: primary buttons.
    pub primary: Rgba,
    pub on_primary: Rgba,
    pub warn: Rgba,
    pub warn_ink: Rgba,
    pub good: Rgba,
    pub bad: Rgba,
    pub info: Rgba,
}

impl Theme {
    pub fn night() -> Self {
        Self {
            day: false,
            bg: rgb(0x161616),
            sidebar: rgb(0x111111),
            card: rgb(0x1a1a1a),
            text: rgb(0xf5f5f5),
            muted: rgb(0xa3a3a3),
            subtle: rgb(0x8a8a8a),
            side: rgb(0xa3a3a3),
            border: rgba(0xffffff1a),
            accent: rgba(0xffffff0f),
            accent2: rgba(0xffffff1a),
            track: rgba(0xffffff14),
            ink: rgb(0xf5f5f5),
            on_ink: rgb(0x161616),
            primary: rgb(0x60a5fa),
            on_primary: rgb(0x0a1628),
            warn: rgb(0xf59e0b),
            warn_ink: rgb(0xfbbf24),
            good: rgb(0x34d399),
            bad: rgb(0xff8a82),
            info: rgb(0x93c5fd),
        }
    }

    pub fn day() -> Self {
        Self {
            day: true,
            bg: rgb(0xfafafa),
            sidebar: rgb(0xf4f4f4),
            card: rgb(0xffffff),
            text: rgb(0x171717),
            muted: rgb(0x525252),
            subtle: rgb(0x737373),
            side: rgb(0x525252),
            border: rgba(0x00000014),
            accent: rgba(0x0000000b),
            accent2: rgba(0x00000014),
            track: rgba(0x00000014),
            ink: rgb(0x171717),
            on_ink: rgb(0xfafafa),
            primary: rgb(0x2563eb),
            on_primary: rgb(0xffffff),
            warn: rgb(0xb86e12),
            warn_ink: rgb(0x9a5b0c),
            good: rgb(0x1f8a4c),
            bad: rgb(0xc44b3c),
            info: rgb(0x2563eb),
        }
    }

    pub fn named(name: &str) -> Self {
        if name == "day" { Self::day() } else { Self::night() }
    }

    /// A colour at a share of its own alpha, for tinted pills.
    pub fn tint(color: Rgba, alpha: f32) -> Rgba {
        Rgba { a: alpha, ..color }
    }
}
