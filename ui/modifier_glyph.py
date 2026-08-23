"""
Pure, read-only computation of which Modifiers are currently pushing a given
stat, and what lifecycle phase each is in — the data behind the
modifier-visibility glyph (see DESIGN.md: "The Modifier-Visibility System").

Same discipline as ui/explain.py: no Qt import here, no mutation, and the
phase/value math is never reimplemented — it's read straight off Modifier.
"""

_PHASE_KEYWORDS = (
    ("pending", "onset"),
    ("phasing in", "ramp"),
    ("fading", "decay"),
    ("expired", "decay"),
)


def _phase_key(modifier) -> str:
    """Modifier.phase_label() is a human sentence ('phasing in (2/4mo)');
    this maps it to the fixed vocabulary the glyph/QML side switches on,
    without duplicating the lifecycle arithmetic phase_label() already does."""
    label = modifier.phase_label()
    for keyword, phase in _PHASE_KEYWORDS:
        if label.startswith(keyword):
            return phase
    return "hold"  # phase_label() returns exactly "active" for the hold phase


def forces_for(state, target: str) -> list[dict]:
    """Every Modifier currently targeting `target`, classified by phase and
    sign. Order is stable (insertion order of state.modifiers) so a glyph's
    tick order doesn't shuffle between refreshes.

    `strength` is present here so a future glyph can length-code ticks
    "loosely to relative strength" per DESIGN.md's Visual Language section,
    but ui/qml/ForceGlyph.qml doesn't consume it yet (Phase 1 renders every
    tick at a fixed width) — deliberately unimplemented, not an oversight;
    real width scaling is follow-up-plan scope."""
    out = []
    for m in state.modifiers:
        if m.target != target:
            continue
        out.append({
            "source": m.source,
            "phase": _phase_key(m),
            "sign": "positive" if m.magnitude >= 0 else "negative",
            "strength": abs(m.current_value()),
        })
    return out


def approval_forces(state) -> list[dict]:
    """The one instantiation of forces_for wired up in Phase 1 — Approval is
    the sole headline vital with real itemized Modifier data
    (target == "approval_bias"; see DESIGN.md's honesty note on why
    Stability and Political Capital don't get this)."""
    return forces_for(state, "approval_bias")
