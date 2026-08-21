"""
Front-of-house screens (Priorities 1–5): main menu, the New Campaign
wizard (country → character → difficulty → generate), and the load
dialog.

Structure: a RootController owns a QStackedWidget and swaps between the
main menu and the wizard; when the wizard finishes it hands a fully
generated GameState to a callback (gui.py) which launches the game
window. This keeps the menu flow entirely separate from the in-game
window — the game doesn't know it was reached via a menu, and the menu
doesn't know how the game runs.

Everything reads from the content/ layer: the country list comes from
content.loader, backgrounds and difficulties from content.campaign_content,
traits from content.traits. Adding a country or a background is a content
edit; these screens pick it up automatically.
"""

from PySide6.QtWidgets import (QWidget, QStackedWidget, QVBoxLayout, QHBoxLayout,
                               QLabel, QPushButton, QComboBox, QLineEdit, QSlider,
                               QListWidget, QListWidgetItem, QDialog, QMessageBox,
                               QButtonGroup, QRadioButton, QFrame, QScrollArea,
                               QCheckBox)
from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QColor

from ui import theme
from ui.widgets_common import section_title, divider, body_label, KeyValueRow

from content import loader
from content import campaign_content
from content import traits as traits_content
from engine.campaign import CampaignConfig, generate_campaign
from engine import persistence


# ═══════════════════════════════════════════════════════════════════════════
# Root controller — swaps between menu and wizard
# ═══════════════════════════════════════════════════════════════════════════

class RootController(QStackedWidget):
    """Owns the menu ↔ wizard flow. Emits campaign_ready(GameState) when a
    campaign is generated (new or loaded), which gui.py connects to the
    game-window launcher."""
    campaign_ready = Signal(object)   # emits a GameState

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(theme.stylesheet())
        self._menu = MainMenu()
        self._menu.new_game.connect(self._start_wizard)
        self._menu.load_game.connect(self._open_load)
        self._menu.settings.connect(self._open_settings)
        self._menu.credits.connect(self._open_credits)
        self._menu.exit_game.connect(self._exit)
        self.addWidget(self._menu)
        self.setCurrentWidget(self._menu)

    def _start_wizard(self):
        wizard = NewCampaignWizard()
        wizard.cancelled.connect(lambda: self._back_to_menu(wizard))
        wizard.finished_config.connect(self._generate)
        self.addWidget(wizard)
        self.setCurrentWidget(wizard)

    def _back_to_menu(self, wizard):
        self.setCurrentWidget(self._menu)
        self.removeWidget(wizard)
        wizard.deleteLater()

    def _generate(self, config):
        try:
            state = generate_campaign(config)
        except Exception as e:
            QMessageBox.warning(self, "Generation Failed", str(e))
            return
        self.campaign_ready.emit(state)

    def _open_load(self):
        dlg = LoadDialog(parent=self)
        if dlg.exec() and dlg.selected_slot:
            try:
                state = persistence.load_campaign(dlg.selected_slot)
            except Exception as e:
                QMessageBox.warning(self, "Load Failed", str(e))
                return
            self.campaign_ready.emit(state)

    def _open_settings(self):
        SettingsDialog(parent=self).exec()

    def _open_credits(self):
        CreditsDialog(parent=self).exec()

    def _exit(self):
        from PySide6.QtWidgets import QApplication
        QApplication.instance().quit()


# ═══════════════════════════════════════════════════════════════════════════
# Main menu (Priority 1)
# ═══════════════════════════════════════════════════════════════════════════

class MainMenu(QWidget):
    new_game = Signal()
    load_game = Signal()
    settings = Signal()
    credits = Signal()
    exit_game = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background: {theme.BG};")
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.addStretch(1)

        title = QLabel("A R D E N I A")
        title.setAlignment(Qt.AlignCenter)
        title.setStyleSheet(
            f"color: {theme.ACCENT}; font-size: 40pt; letter-spacing: 12px;")
        outer.addWidget(title)

        subtitle = QLabel("a political simulation")
        subtitle.setAlignment(Qt.AlignCenter)
        subtitle.setStyleSheet(
            f"color: {theme.INK_DIM}; font-size: {theme.FONT_SIZE_PT}pt; letter-spacing: 4px;")
        outer.addWidget(subtitle)
        outer.addSpacing(40)

        button_col = QVBoxLayout()
        button_col.setSpacing(8)
        button_col.setAlignment(Qt.AlignCenter)
        for label, signal in [("New Game", self.new_game), ("Load Game", self.load_game),
                              ("Settings", self.settings), ("Credits", self.credits),
                              ("Exit", self.exit_game)]:
            btn = QPushButton(label)
            btn.setFixedWidth(240)
            btn.setFixedHeight(38)
            btn.clicked.connect(signal.emit)
            button_col.addWidget(btn, alignment=Qt.AlignCenter)
        outer.addLayout(button_col)

        outer.addStretch(2)

        footer = QLabel("Reusing the existing simulation engine · v0 campaign framework")
        footer.setAlignment(Qt.AlignCenter)
        footer.setStyleSheet(f"color: {theme.INK_FAINT}; font-size: {theme.FONT_SIZE_SM}pt;")
        outer.addWidget(footer)


# ═══════════════════════════════════════════════════════════════════════════
# New Campaign wizard (Priority 2) — modular step flow
# ═══════════════════════════════════════════════════════════════════════════

class NewCampaignWizard(QWidget):
    """
    A guided multi-step setup. Steps are modular: each is a QWidget with a
    collect() method that writes its choices into the shared config. Adding
    a step later means adding one widget to the _steps list — the flow,
    progress display, and next/back handling adapt automatically.
    """
    cancelled = Signal()
    finished_config = Signal(object)   # emits a CampaignConfig

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setStyleSheet(f"background: {theme.BG};")
        self.config = CampaignConfig(country_id="ardenia")

        root = QVBoxLayout(self)
        root.setContentsMargins(24, 18, 24, 18)
        root.setSpacing(10)

        self._header = QLabel()
        self._header.setStyleSheet(
            f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_LG}pt; letter-spacing: 2px;")
        root.addWidget(self._header)
        root.addWidget(divider())

        self._stack = QStackedWidget()
        root.addWidget(self._stack, stretch=1)

        # The modular step list. Each entry: (title, widget).
        self._country_step = CountrySelectStep()
        self._character_step = CharacterStep()
        self._difficulty_step = DifficultyStep()
        self._summary_step = SummaryStep()
        self._steps = [
            ("Country Selection", self._country_step),
            ("Character Creation", self._character_step),
            ("Difficulty", self._difficulty_step),
            ("Confirm & Generate", self._summary_step),
        ]
        for _, w in self._steps:
            self._stack.addWidget(w)

        # Nav bar
        nav = QHBoxLayout()
        self._back_btn = QPushButton("◀ Back")
        self._back_btn.clicked.connect(self._go_back)
        self._next_btn = QPushButton("Next ▶")
        self._next_btn.clicked.connect(self._go_next)
        cancel_btn = QPushButton("Cancel")
        cancel_btn.clicked.connect(self.cancelled.emit)
        nav.addWidget(cancel_btn)
        nav.addStretch(1)
        nav.addWidget(self._back_btn)
        nav.addWidget(self._next_btn)
        root.addLayout(nav)

        self._index = 0
        self._show_step(0)

    def _show_step(self, i):
        self._index = i
        title, widget = self._steps[i]
        self._header.setText(f"NEW CAMPAIGN  ·  {title}  ({i + 1}/{len(self._steps)})")
        self._stack.setCurrentWidget(widget)
        self._back_btn.setEnabled(i > 0)
        self._next_btn.setText("Generate ▶" if i == len(self._steps) - 1 else "Next ▶")
        # Let a step refresh from the config as we arrive (e.g. summary,
        # or character step needing the chosen country's parties).
        if hasattr(widget, "on_enter"):
            widget.on_enter(self.config)

    def _go_next(self):
        _, widget = self._steps[self._index]
        if hasattr(widget, "collect"):
            widget.collect(self.config)
        if self._index == len(self._steps) - 1:
            self.finished_config.emit(self.config)
            return
        self._show_step(self._index + 1)

    def _go_back(self):
        # Preserve any choices made on the current step before going back.
        _, widget = self._steps[self._index]
        if hasattr(widget, "collect"):
            widget.collect(self.config)
        if self._index > 0:
            self._show_step(self._index - 1)


# ── Step: country selection (Priority 3) ────────────────────────────────────

# Which countries you may currently START a campaign as. The other eight
# remain fully present in the world — AI actors, diplomacy targets, map
# neighbours — they simply aren't playable yet, and the wizard says so
# rather than hiding them.
PLAYABLE_COUNTRY_IDS = {"ardenia"}


class CountrySelectStep(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QHBoxLayout(self)
        layout.setSpacing(14)

        left = QWidget()
        left_col = QVBoxLayout(left)
        left_col.setContentsMargins(0, 0, 0, 0)
        left_col.setSpacing(4)
        left.setFixedWidth(240)      # fits the longest "… · Coming Soon" row

        self._list = QListWidget()
        # No horizontal scrollbar for a name that runs long — elide instead.
        self._list.setHorizontalScrollBarPolicy(Qt.ScrollBarAlwaysOff)
        self._list.setTextElideMode(Qt.ElideRight)
        # Playable countries first, so the one you can pick is at the top.
        self._summaries = sorted(
            loader.list_country_summaries(),
            key=lambda s: (s["id"] not in PLAYABLE_COUNTRY_IDS, s["name"]))
        for summ in self._summaries:
            playable = summ["id"] in PLAYABLE_COUNTRY_IDS
            item = QListWidgetItem(summ["name"] if playable
                                   else f"{summ['name']}   ·  Coming Soon")
            item.setData(Qt.UserRole, summ["id"])
            if not playable:
                # Visible, greyed, and genuinely unselectable — no flags for
                # selection or interaction at all.
                item.setFlags(Qt.NoItemFlags)
                item.setForeground(QColor(theme.INK_DIM))
                item.setToolTip(
                    f"{summ['name']} is not yet playable — "
                    f"{summ.get('meta', {}).get('short_description', '')}")
            self._list.addItem(item)
        self._list.currentRowChanged.connect(self._on_select)
        left_col.addWidget(self._list, stretch=1)

        note = body_label("More nations become playable in a future update.",
                          dim=True, small=True)
        note.setWordWrap(True)
        left_col.addWidget(note)
        layout.addWidget(left)

        self._detail = QScrollArea()
        self._detail.setWidgetResizable(True)
        self._detail.setFrameShape(QFrame.NoFrame)
        self._detail_inner = QWidget()
        self._detail_layout = QVBoxLayout(self._detail_inner)
        self._detail_layout.setSpacing(4)
        self._detail.setWidget(self._detail_inner)
        layout.addWidget(self._detail, stretch=1)

        # Ardenia is sorted first and is the only selectable entry.
        first_playable = next((i for i, s in enumerate(self._summaries)
                               if s["id"] in PLAYABLE_COUNTRY_IDS), None)
        if first_playable is not None:
            self._list.setCurrentRow(first_playable)

    def _clear_detail(self):
        while self._detail_layout.count():
            item = self._detail_layout.takeAt(0)
            w = item.widget()
            if w:
                w.deleteLater()

    def _on_select(self, row):
        if row < 0 or row >= len(self._summaries):
            return
        summ = self._summaries[row]
        meta = summ.get("meta", {})
        self._clear_detail()
        L = self._detail_layout

        name = QLabel(summ["name"])
        name.setStyleSheet(f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_LG}pt;")
        L.addWidget(name)
        L.addWidget(body_label(meta.get("short_description", ""), small=True))
        L.addWidget(divider())

        L.addWidget(KeyValueRow("Government", summ["regime_type"].replace("_", " ")))
        L.addWidget(KeyValueRow("Difficulty", meta.get("difficulty", "normal").title(),
                                _difficulty_color(meta.get("difficulty", "normal"))))

        strengths = meta.get("strengths", [])
        weaknesses = meta.get("weaknesses", [])
        if strengths:
            L.addWidget(section_title("STRENGTHS"))
            for s in strengths:
                L.addWidget(body_label(f"+ {s}", small=True))
        if weaknesses:
            L.addWidget(section_title("WEAKNESSES"))
            for w in weaknesses:
                L.addWidget(body_label(f"– {w}", small=True))

        traits = summ.get("national_traits", [])
        if traits:
            L.addWidget(section_title("NATIONAL CHARACTER"))
            for tname, tdesc in traits_content.describe_traits(traits):
                L.addWidget(body_label(f"{tname}: {tdesc}", dim=True, small=True))
        L.addStretch(1)

    def collect(self, config):
        row = self._list.currentRow()
        if 0 <= row < len(self._summaries):
            chosen = self._summaries[row]["id"]
            # Belt and braces: the list can't select a locked country, but a
            # campaign must never start as one regardless of how we got here.
            if chosen in PLAYABLE_COUNTRY_IDS:
                config.country_id = chosen


def _difficulty_color(diff):
    return {"easy": theme.GOOD, "normal": theme.WARN, "hard": theme.CRITICAL}.get(diff, theme.INK)


# ── Step: character creation (Priority 4) ───────────────────────────────────

class CharacterStep(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setSpacing(8)

        layout.addWidget(section_title("YOUR CHARACTER"))

        # Ardenia supplies the situation; the party and position determine
        # which side of that situation the player enters from.
        premise = body_label(
            "Choose the party you lead and whether the Reckoning places it in government "
            "or opposition. Party affiliation supplies your default ideology; the sliders "
            "let your leader diverge from it. The same simulation systems govern every path.",
            dim=True, small=True)
        premise.setWordWrap(True)
        layout.addWidget(premise)
        layout.addWidget(divider())

        # Name
        name_row = QHBoxLayout()
        name_row.addWidget(_field_label("Name"))
        self._name = QLineEdit()
        self._name.setPlaceholderText("(leave blank for the country default)")
        name_row.addWidget(self._name, stretch=1)
        layout.addLayout(name_row)

        # Political party (populated from the chosen country on_enter)
        party_row = QHBoxLayout()
        party_row.addWidget(_field_label("Political Party"))
        self._party = QComboBox()
        self._party.currentIndexChanged.connect(self._update_position_desc)
        party_row.addWidget(self._party, stretch=1)
        layout.addLayout(party_row)

        position_row = QHBoxLayout()
        position_row.addWidget(_field_label("Opening Position"))
        self._opening_role = QComboBox()
        self._opening_role.addItem("Contextual to party", "contextual")
        self._opening_role.addItem("Lead a government", "government")
        self._opening_role.addItem("Begin in opposition", "opposition")
        self._opening_role.currentIndexChanged.connect(self._update_position_desc)
        position_row.addWidget(self._opening_role, stretch=1)
        layout.addLayout(position_row)
        self._position_desc = body_label("", dim=True, small=True)
        self._position_desc.setWordWrap(True)
        layout.addWidget(self._position_desc)

        # Background
        layout.addWidget(section_title("POLITICAL BACKGROUND"))
        self._bg = QComboBox()
        for bg in campaign_content.all_backgrounds():
            self._bg.addItem(bg.name, bg.id)
        self._bg.currentIndexChanged.connect(self._update_bg_desc)
        layout.addWidget(self._bg)
        self._bg_desc = body_label("", dim=True, small=True)
        layout.addWidget(self._bg_desc)

        # Optional ideology sliders
        layout.addWidget(section_title("IDEOLOGY (optional)"))
        self._econ = _labeled_slider("Economic  (left ◀ ▶ right)")
        self._soc = _labeled_slider("Social  (traditional ◀ ▶ progressive)")
        layout.addLayout(self._econ["row"])
        layout.addLayout(self._soc["row"])
        self._use_ideology = QRadioButton("Override the character's default ideology")
        self._use_ideology.setStyleSheet(f"color: {theme.INK_DIM};")
        layout.addWidget(self._use_ideology)

        layout.addStretch(1)
        self._update_bg_desc()

    def on_enter(self, config):
        # Populate the party dropdown from the chosen country's factions.
        self._party.clear()
        self._party.addItem("(country default)", None)
        try:
            data = loader.load_country_data(config.country_id)
            for f in data.get("factions", []):
                self._party.addItem(f["name"], f["id"])
        except Exception:
            pass
        self._update_position_desc()

    def _update_position_desc(self):
        if not hasattr(self, "_position_desc"):
            return
        party_name = self._party.currentText() or "the selected party"
        role = self._opening_role.currentData()
        if role == "government":
            text = (f"{party_name} will lead a coalition assembled from the Reckoning's "
                    "seat totals and ideological compatibility.")
        elif role == "opposition":
            text = (f"{party_name} will begin outside government. A rival party will form "
                    "the administration, and government-only actions remain unavailable.")
        else:
            text = ("The authored result decides the side of power: coalition parties lead "
                    "a government; parties outside it begin in opposition.")
        self._position_desc.setText(text)

    def _update_bg_desc(self):
        bg = campaign_content.get_background(self._bg.currentData())
        self._bg_desc.setText(bg.description if bg else "")

    def collect(self, config):
        config.leader_name = self._name.text().strip() or None
        config.party_id = self._party.currentData()
        config.opening_role = self._opening_role.currentData()
        config.background_id = self._bg.currentData()
        if self._use_ideology.isChecked():
            config.ideology_economic = self._econ["slider"].value() / 100.0
            config.ideology_social = self._soc["slider"].value() / 100.0
        else:
            config.ideology_economic = None
            config.ideology_social = None


# ── Step: difficulty (Priority 5) ───────────────────────────────────────────

class DifficultyStep(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        layout = QVBoxLayout(self)
        layout.setSpacing(8)
        layout.addWidget(section_title("DIFFICULTY"))

        self._group = QButtonGroup(self)
        self._buttons = {}
        for diff in campaign_content.all_difficulties():
            btn = QRadioButton(diff.name)
            btn.setStyleSheet(f"color: {_difficulty_color(diff.id)}; font-size: {theme.FONT_SIZE_PT}pt;")
            self._group.addButton(btn)
            self._buttons[diff.id] = btn
            layout.addWidget(btn)
            layout.addWidget(body_label(diff.description, dim=True, small=True))
        self._buttons["normal"].setChecked(True)

        layout.addWidget(divider())
        layout.addWidget(section_title("CAMPAIGN SEED (optional)"))
        seed_row = QHBoxLayout()
        seed_row.addWidget(_field_label("Seed"))
        self._seed = QLineEdit()
        self._seed.setPlaceholderText("(blank = derived from your choices)")
        seed_row.addWidget(self._seed, stretch=1)
        layout.addLayout(seed_row)
        layout.addWidget(body_label(
            "The same seed and the same choices always generate the same campaign.",
            dim=True, small=True))

        layout.addWidget(divider())
        layout.addWidget(section_title("THE FIRST NINETY DAYS"))
        self._skip_guidance = QCheckBox("Skip the guided opening")
        self._skip_guidance.setStyleSheet(f"font-size: {theme.FONT_SIZE_PT}pt;")
        layout.addWidget(self._skip_guidance)
        layout.addWidget(body_label(
            "A new government meets six regions, six ministries, seven spending "
            "envelopes and twelve party currents at once. Left on, a short note "
            "introduces one of them at a time over the first months. It never "
            "blocks an action or insists on an order, and each note goes away "
            "for good once read.",
            dim=True, small=True))

        layout.addStretch(1)

    def collect(self, config):
        for did, btn in self._buttons.items():
            if btn.isChecked():
                config.difficulty_id = did
                break
        seed_text = self._seed.text().strip()
        if seed_text:
            try:
                config.seed = int(seed_text)
            except ValueError:
                config.seed = abs(hash(seed_text)) % (2**31)
        else:
            config.seed = None
        config.guidance_enabled = not self._skip_guidance.isChecked()


# ── Step: summary ───────────────────────────────────────────────────────────

class SummaryStep(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._layout = QVBoxLayout(self)
        self._layout.setSpacing(4)

    def on_enter(self, config):
        while self._layout.count():
            item = self._layout.takeAt(0)
            w = item.widget()
            if w:
                w.deleteLater()
        L = self._layout

        try:
            data = loader.load_country_data(config.country_id)
            country_name = data["name"]
            default_player = data.get("default_player", {})
        except Exception:
            country_name = config.country_id
            default_player = {}

        L.addWidget(section_title("REVIEW YOUR CAMPAIGN"))
        L.addWidget(KeyValueRow("Country", country_name))
        L.addWidget(KeyValueRow("Leader", config.leader_name or default_player.get("name", "(default)")))
        party_id = config.party_id or default_player.get("faction_id", "(default)")
        factions = {f.get("id"): f for f in data.get("factions", [])} if 'data' in locals() else {}
        party = factions.get(party_id, {}).get("name", party_id)
        L.addWidget(KeyValueRow("Party", str(party)))
        role_names = {
            "contextual": "Contextual to party",
            "government": "Lead government",
            "opposition": "Begin in opposition",
        }
        L.addWidget(KeyValueRow("Opening position",
                                role_names.get(config.opening_role, config.opening_role)))
        if config.ideology_economic is None:
            ideology = "Party position"
        else:
            ideology = (f"Economic {config.ideology_economic:+.2f} · "
                        f"Social {config.ideology_social:+.2f}")
        L.addWidget(KeyValueRow("Ideology", ideology))
        bg = campaign_content.get_background(config.background_id)
        L.addWidget(KeyValueRow("Background", bg.name if bg else config.background_id))
        diff = campaign_content.get_difficulty(config.difficulty_id)
        L.addWidget(KeyValueRow("Difficulty", diff.name if diff else config.difficulty_id,
                                _difficulty_color(config.difficulty_id)))
        L.addWidget(KeyValueRow("Seed", str(config.resolved_seed())))
        L.addWidget(divider())
        L.addWidget(body_label("Click Generate to create your campaign and enter the new parliament.", small=True))
        L.addStretch(1)

    def collect(self, config):
        pass


# ═══════════════════════════════════════════════════════════════════════════
# Load dialog (Priority 9)
# ═══════════════════════════════════════════════════════════════════════════

class LoadDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Load Campaign")
        self.setMinimumSize(460, 380)
        self.setStyleSheet(theme.stylesheet())
        self.selected_slot = None

        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 12)
        root.setSpacing(8)
        header = QLabel("LOAD CAMPAIGN")
        header.setStyleSheet(f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_LG}pt; letter-spacing: 2px;")
        root.addWidget(header)
        root.addWidget(divider())

        self._list = QListWidget()
        self._saves = persistence.list_saves()
        if self._saves:
            for sv in self._saves:
                label = f"{sv['label']}"
                if sv["slot"] == "autosave":
                    label = f"[autosave] {label}"
                item = QListWidgetItem(label)
                item.setData(Qt.UserRole, sv["slot"])
                self._list.addItem(item)
        else:
            item = QListWidgetItem("(no saved campaigns)")
            item.setForeground(_dim())
            self._list.addItem(item)
        root.addWidget(self._list, stretch=1)

        nav = QHBoxLayout()
        cancel = QPushButton("Cancel")
        cancel.clicked.connect(self.reject)
        load = QPushButton("Load")
        load.clicked.connect(self._do_load)
        delete = QPushButton("Delete")
        delete.clicked.connect(self._do_delete)
        nav.addWidget(cancel)
        nav.addStretch(1)
        nav.addWidget(delete)
        nav.addWidget(load)
        root.addLayout(nav)

    def _do_load(self):
        item = self._list.currentItem()
        if item and item.data(Qt.UserRole):
            self.selected_slot = item.data(Qt.UserRole)
            self.accept()

    def _do_delete(self):
        item = self._list.currentItem()
        if item and item.data(Qt.UserRole):
            slot = item.data(Qt.UserRole)
            persistence.delete_save(slot)
            self._list.takeItem(self._list.row(item))


# ═══════════════════════════════════════════════════════════════════════════
# Settings & Credits (Priority 1 — present but light)
# ═══════════════════════════════════════════════════════════════════════════

class SettingsDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Settings")
        self.setMinimumSize(380, 240)
        self.setStyleSheet(theme.stylesheet())
        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 12)
        header = QLabel("SETTINGS")
        header.setStyleSheet(f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_LG}pt; letter-spacing: 2px;")
        root.addWidget(header)
        root.addWidget(divider())
        root.addWidget(body_label(
            "Settings are a placeholder for now — the campaign framework wires the "
            "screen in so options (autosave frequency, display density, and so on) "
            "can be added here later without touching the game window.", dim=True, small=True))
        root.addStretch(1)
        close = QPushButton("Close")
        close.clicked.connect(self.accept)
        root.addWidget(close, alignment=Qt.AlignRight)


class CreditsDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Credits")
        self.setMinimumSize(380, 260)
        self.setStyleSheet(theme.stylesheet())
        root = QVBoxLayout(self)
        root.setContentsMargins(14, 12, 14, 12)
        header = QLabel("CREDITS")
        header.setStyleSheet(f"color: {theme.ACCENT}; font-size: {theme.FONT_SIZE_LG}pt; letter-spacing: 2px;")
        root.addWidget(header)
        root.addWidget(divider())
        root.addWidget(body_label(
            "Ardenia — a political simulation.\n\n"
            "A real-time-with-pause political simulator built around an interconnected "
            "economy, coalition politics, elections, and long-term policy "
            "consequences.\n\n"
            "Inspired by the classic political strategy games of the 1980s and 90s.",
            small=True))
        root.addStretch(1)
        close = QPushButton("Close")
        close.clicked.connect(self.accept)
        root.addWidget(close, alignment=Qt.AlignRight)


# ═══════════════════════════════════════════════════════════════════════════
# Small shared helpers
# ═══════════════════════════════════════════════════════════════════════════

def _field_label(text):
    lbl = QLabel(text)
    lbl.setFixedWidth(130)
    lbl.setStyleSheet(f"color: {theme.INK_DIM};")
    return lbl


def _labeled_slider(caption):
    row = QVBoxLayout()
    cap = QLabel(caption)
    cap.setStyleSheet(f"color: {theme.INK_DIM}; font-size: {theme.FONT_SIZE_SM}pt;")
    slider = QSlider(Qt.Horizontal)
    slider.setRange(-100, 100)
    slider.setValue(0)
    row.addWidget(cap)
    row.addWidget(slider)
    return {"row": row, "slider": slider}


def _dim():
    from PySide6.QtGui import QBrush, QColor
    return QBrush(QColor(theme.INK_DIM))
