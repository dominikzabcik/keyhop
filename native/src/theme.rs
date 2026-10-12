//! The design sketch's tokens (design/keyhop-v2/index.html), night and day.

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
            bg: rgb(0x101010),
            sidebar: rgb(0x141414),
            card: rgb(0x1b1b1b),
            text: rgb(0xececec),
            muted: rgb(0x9a9a9a),
            subtle: rgb(0x6f6f6f),
            side: rgb(0x8d8d8d),
            border: rgba(0xffffff14),
            accent: rgba(0xffffff0f),
            accent2: rgba(0xffffff1a),
            track: rgba(0xffffff14),
            ink: rgb(0xf2f2f2),
            on_ink: rgb(0x101010),
            warn: rgb(0xe3a64f),
            warn_ink: rgb(0xf0c27a),
            good: rgb(0x5cc98a),
            bad: rgb(0xee7a69),
            info: rgb(0x7eb0f2),
        }
    }

    pub fn day() -> Self {
        Self {
            day: true,
            bg: rgb(0xf4f4f1),
            sidebar: rgb(0xefefec),
            card: rgb(0xffffff),
            text: rgb(0x1c1c1c),
            muted: rgb(0x5f5f5a),
            subtle: rgb(0x8a8a84),
            side: rgb(0x5c5c57),
            border: rgba(0x00000014),
            accent: rgba(0x0000000b),
            accent2: rgba(0x00000014),
            track: rgba(0x00000014),
            ink: rgb(0x1c1c1c),
            on_ink: rgb(0xf4f4f1),
            warn: rgb(0xb86e12),
            warn_ink: rgb(0x9a5b0c),
            good: rgb(0x1f8a4c),
            bad: rgb(0xc44b3c),
            info: rgb(0x2f6fbe),
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
